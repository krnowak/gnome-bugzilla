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

# This code for this is in ./extensions/AttachmentStatus/lib/Util.pm
use Bugzilla::Extension::AttachmentStatus::Util;

use List::MoreUtils qw(any);

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.

# Either rename already existing 'status' column to
# 'gnome_attachment_status' or create it.
sub install_update_db {
    my ($class, $args) = @_;

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
    my ($class, $args) = @_;
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

    $schema->{g_a_s()} = $definition;
}

sub object_columms {
    my ($class, $columns) = @_;

    as_dbg('object columns, class: ', $class, ', columns: ', $columns, ', bz_a: ', bz_a());
    if ($class->isa(bz_a())) {
        as_dbg('    inside ', bz_a());
        push (@{$columns}, g_a_s());
    }
}

sub object_update_columns {
    my ($class, $columns) = @_;

    as_dbg('object update columns, class: ', $class, ', columns: ', $columns, ', bz_a: ', bz_a());
    if ($class->isa(bz_a())) {
        as_dbg('    inside ', bz_a());
        push (@{$columns}, g_a_s());
    }
}

sub object_validators {
    my ($class, $validators) = @_;

    as_dbg('object validators, class: ', $class, ', validators: ', $validators, ', bz_a: ', bz_a());
    if ($class->isa(bz_a())) {
        as_dbg('    inside ', bz_a());
        if (exists ($validators->{g_a_s()})) {
            as_dbg('    one already exists');
            my $old_validator = $validators->{g_a_s()};
            $validators->{g_a_s()} = sub {
                my ($class, $value, $field, $all_fields) = @_;

                validate_status($class, &{$old_validator}(@_), $field, $all_fields);
            };
        } else {
            as_dbg('    none exists so far');
            $validators->{g_a_s()} = \&validate_status;
        }
    }
}

sub object_end_of_create_validators {
    my ($class, $params) = @_;

    as_dbg('object end of create validators, class: ', $class, ', params: ', $params, ', bz_a: ', bz_a());
    if ($class->isa(bz_a())) {
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
    }
}

sub enabled {
    as_dbg('we are enabled');
    1;
}

__PACKAGE__->NAME;
