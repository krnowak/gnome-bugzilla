# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GnomeAttachmentStatus;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

# The code for this is in ./extensions/GnomeAttachmentStatus/lib/*.pm
use Bugzilla::Extension::GnomeAttachmentStatus::Util;
use Bugzilla::Extension::GnomeAttachmentStatus::Ops;

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

# Add 'gnome_attachment_status' table with almost the same schema as
# 'resolution' - 'resolution' has typical selectable field-like
# schema. One addition is a description column.
#
# It would be better to have a hook for adding more enum initial
# values instead (see Bugzilla::DB::bz_populate_enum_tables).
sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{'schema'};

    add_gnome_attachment_status_table_to_schema($schema);
}

sub object_columns {
    my ($self, $args) = @_;
    if ($args->{'class'}->isa(bz_a())) {
        push (@{$args->{'columns'}}, g_a_s());
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my $object = $args->{'object'};

    if ($object->isa(bz_a())) {
        push (@{$args->{'columns'}}, g_a_s());
        cgi_hack_update($object);
    }
}

sub object_validators {
    my ($self, $args) = @_;

    if ($args->{'class'}->isa(bz_a())) {
        my $validators = $args->{'validators'};
        if (exists ($validators->{g_a_s()})) {
            my $old_validator = $validators->{g_a_s()};
            $validators->{g_a_s()} = sub {
                my ($class, $value, $field) = @_;

                validate_status($class, &{$old_validator}(@_), $field);
            };
        } else {
            $validators->{g_a_s()} = \&validate_status;
        }
    }
}

sub object_end_of_create_validators {
    my ($self, $args) = @_;

    if ($args->{'class'}->isa(bz_a())) {
        my $params = $args->{'params'};
        # assuming that status, if exists, is already validated
        unless (defined $params->{g_a_s()} and $params->{'ispatch'}
                and Bugzilla->user->in_group('editbugs'))
        {
            $params->{g_a_s()} = 'none';
        }
    }
}

sub template_before_process {
    my ($self, $args) = @_;
    my $handlers = $self->{'template_handlers'};
    my $file = $args->{'file'};

    if (exists ($handlers->{$file})) {
        my $vars = $args->{'vars'};
        my $context = $args->{'context'};

        $handlers->{$file}($file, $vars, $context);
    }
}

# Either rename already existing 'status' column to
# 'gnome_attachment_status' or create it. This should be a part of
# install_update_db, but this hook is a PITA when dealing with columns
# that have foreign key constraints. In our case, we wanted to remove
# a foreign key constraint from status column, but it is not really
# removed from schema, so on next run of checksetup it would be
# recreated. To remove it for good, we need to remove the status
# column. To do that, we need to remove the foreign key constraint
# anyway first, but it is not removed, because when install_update_db
# hook is run, foreign keys are not yet set up, so bz_drop_fk does
# nothing, but foreign key already exists in database. Without foreign
# key removed, we are getting errors when dropping a column.
#
# In short: argh!
sub install_before_final_checks
{
    if (fresh) {
        install_gnome_attachment_status;
    } elsif (updating) {
        update_gnome_attachment_status;
    } else {
        print "install_update_db: we are already updated\n";
        # Do nothing, we are already updated.
    }
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
