# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AttachmentStatus;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

# The code for this is in ./extensions/AttachmentStatus/lib/*.pm
use Bugzilla::Extension::AttachmentStatus::Util;
use Bugzilla::Extension::AttachmentStatus::Ops;

use List::MoreUtils qw(any);

our $VERSION = '0.01';

sub new {
    my ($class) = @_;
    my $handlers = {'attachment/edit.html.tmpl' => \&attachment_edit_handler,
                    'attachment/list.html.tmpl' => \&attachment_list_handler
    };
    my $instance = {'template_handlers' => $handlers};

    # TODO: Store a checksum of original attachment/list.html.tmpl and
    # compare it to checksum of actual attachment/list.html.tmpl. Bail
    # out when they are different. That way we can be notified when
    # original template changed, so maybe we could be able to
    # incorporate the changes to our override.

    # BEWARE: Do not even think of using template_include_path from
    # Bugzilla::Install::Util here - in my case it causes some deep
    # recursion, httpd went berserk and my computer became a zombie.
    update_choice_class_map();
    return $class->SUPER::new($instance);
}

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.

# Either rename already existing 'status' column to
# 'gnome_attachment_status' or create it.
sub install_update_db {
    if (fresh) {
        install_gnome_attachment_status;
    } elsif (updating) {
        update_gnome_attachment_status;
    } else {
        print "install_update_db: we are already updated\n";
        # Do nothing, we are already updated.
    }
}

# Add 'gnome_attachment_status' table with almost the same schema as
# 'resolution' - 'resolution' has typical selectable field-like
# schema. One addition is a description column.
#
# It would be better to have a hook for adding more enum initial
# values instead (see Bugzilla::DB::bz_populate_enum_tables).
sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{'schema'};
    my $definition = {
        FIELDS => [
            id                  => {TYPE => 'SMALLSERIAL', NOTNULL => 1,
                                    PRIMARYKEY => 1},
            value               => {TYPE => 'varchar(64)', NOTNULL => 1},
            sortkey             => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => 0},
            isactive            => {TYPE => 'BOOLEAN', NOTNULL => 1,
                                    DEFAULT => 'TRUE'},
            visibility_value_id => {TYPE => 'INT2'},
            description         => {TYPE => 'MEDIUMTEXT', NOTNULL => 1}
        ],
        INDEXES => [
            gnome_attachment_status_value_idx   => {FIELDS => ['value'],
                                                    TYPE => 'UNIQUE'},
            gnome_attachment_status_sortkey_idx => ['sortkey', 'value'],
            gnome_attachment_status_visibility_value_id_idx => ['visibility_value_id'],
        ]
    };

    # Create the table unconditionally. If we are updating from old
    # setup, we will just remove the attachment_status table.
    $schema->{g_a_s()} = $definition;
}

sub object_columns {
    my ($self, $args) = @_;
    as_dbg('object columns, self: ', $self, ', args: ', $args, ', bz_a: ', bz_a());
    if ($args->{'class'}->isa(bz_a())) {
        as_dbg('    inside ', bz_a());
        push (@{$args->{'columns'}}, g_a_s());
        as_dbg('    after ', bz_a(), ', args: ', $args);
    } else {
        as_dbg('    ', $args->{'class'}, ' is not a ', bz_a());
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my $object = $args->{'object'};

    as_dbg('object update columns, self: ', $self, ', args: ', $args, ', bz_a: ', bz_a());
    if ($object->isa(bz_a())) {
        as_dbg('    inside ', bz_a());
        push (@{$args->{'columns'}}, g_a_s());
        as_dbg('    after ', bz_a(), ', args: ', $args);
        cgi_hack_update($object);
    } else {
        as_dbg('    ', $args->{'object'}, ' is not a ', bz_a());
    }
}

sub object_validators {
    my ($self, $args) = @_;

    as_dbg('object validators, self: ', $self, ', args: ', $args, ', bz_a: ', bz_a());
    if ($args->{'class'}->isa(bz_a())) {
        my $validators = $args->{'validators'};
        as_dbg('    inside ', bz_a());
        if (exists ($validators->{g_a_s()})) {
            as_dbg('    one already exists');
            my $old_validator = $validators->{g_a_s()};
            $validators->{g_a_s()} = sub {
                my ($class, $value, $field) = @_;

                validate_status($class, &{$old_validator}(@_), $field);
            };
        } else {
            as_dbg('    none exists so far');
            $validators->{g_a_s()} = \&validate_status;
        }
    } else {
        as_dbg('    ', $args->{'class'}, ' is not a ', bz_a());
    }
}

sub object_end_of_create_validators {
    my ($self, $args) = @_;

    as_dbg('object end of create validators, self: ', $self, ', args: ', $args, ', bz_a: ', bz_a());
    if ($args->{'class'}->isa(bz_a())) {
        my $params = $args->{'params'};
        # assuming that status, if exists, is already validated
        as_dbg('    inside ', bz_a());
        unless (defined $params->{g_a_s()} and $params->{'ispatch'}
                and Bugzilla->user->in_group('editbugs'))
        {
            as_dbg('    not a patch or no gnome attachment status parameter or we are not in editbugs group - setting attachment status to none');
            $params->{g_a_s()} = 'none';
        } else {
            as_dbg('    left alone');
        }
    } else {
        as_dbg('    ', $args->{'class'}, ' is not a ', bz_a());
    }
}

sub template_before_process {
    my ($self, $args) = @_;
    my $handlers = $self->{'template_handlers'};
    my $file = $args->{'file'};

    as_dbg('template before process, self: ', $self, ', args: ', $args);
    if (exists ($handlers->{$file})) {
        my $vars = $args->{'vars'};
        my $context = $args->{'context'};

        $handlers->{$file}($file, $vars, $context);
    }
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
