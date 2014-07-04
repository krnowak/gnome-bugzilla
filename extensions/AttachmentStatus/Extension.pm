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
use base qw(Bugzilla::Extension);

# This code for this is in ./extensions/AttachmentStatus/lib/Util.pm
use Bugzilla::Extension::AttachmentStatus::Util;

use List::MoreUtils qw(any);

our $VERSION = '0.01';
my $g_a_s = 'gnome_attachment_status';
my $bz_a = 'Bugzilla::Attachment';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.

# Either rename already existing 'status' column to
# 'gnome_attachment_status' or create it.
sub install_update_db {
    my ($class, $args) = @_;

    if ($class->isa($bz_a)) {
        my $dbh = Bugzilla->dbh;
        my $schema = $dbh->_bz_schema();
        my @columns = $schema->get_table_columns('attachment');
        my $definition = {TYPE => 'varchar(64)',
                          NOTNULL => 1,
                          REFERENCES => {TABLE => $g_a_s,
                                         COLUMN => 'value',
                                         DELETE => 'CASCADE'}};

        if (any {$_ eq 'status'} @columns) {
            $dbh->bz_rename_column('attachment', 'status', $g_a_s);
            $dbh->bz_alter_column('attachment', $g_a_s, $definition, 'none');
            $dbh->bz_drop_table('attachment_status');
        }
        unless (any {$_ eq $g_a_s} @columns) {
            $dbh->bz_add_column('attachment', $g_a_s, $definition, 'none');
        }
    }
}

# Add 'gnome_attachment_status' table with the same schema as
# 'resolution' - 'resolution' has typical selectable field-like
# schema.
#
# It would be better to have a hook for adding more enum initial
# values instead (see Bugzilla::DB::bz_populate_enum_tables).
#
# TODO: Add a description column.
sub db_schema_abstract_schema {
    my ($class, $args) = @_;

    # TODO: Maybe use DB::Schema::FIELD_TABLE_SCHEMA?
    $args->{'schema'}->{$g_a_s} = {
        'FIELDS' => $args->{'schema'}->{'resolution'}->{'FIELDS'}
    };
}

sub object_columms {
    my ($class, $columns) = @_;

    if ($class->isa($bz_a)) {
	push (@{$columns}, $g_a_s);
    }
}

sub object_update_columns {
    my ($class, $columns) = @_;

    if ($class->isa($bz_a)) {
	push (@{$columns}, $g_a_s);
    }
}

sub validate_status {
    my ($class, $value) = @_;

    if ($class->isa($bz_a)) {
        my $field = Bugzilla::Field::Choice->type($g_a_s)->check($value);

        return $field->name;
    }

    return $value;
}

sub object_validators {
    my ($class, $validators) = @_;

    if ($class->isa($bz_a)) {
	if (exists ($validators->{$g_a_s})) {
	    my $old_validator = $validators->{$g_a_s};
	    $validators->{$g_a_s} = sub {
                my ($class, $value, $field, $all_fields) = @_;

                validate_status($class, &{$old_validator}(@_), $field, $all_fields);
            };
	} else {
	    $validators->{$g_a_s} = \&validate_status;
	}
    }
}

sub object_end_of_create_validators {
    my ($class, $params) = @_;

    if ($class->isa($bz_a)) {
        # assuming that status, if exists, is already validated
        unless (defined $params->{$g_a_s} and $params->{'ispatch'}
                and Bugzilla->user->in_group('editbugs'))
        {
            $params->{$g_a_s} = 'none';
        }
    }
}

sub install_before_final_checks {
    my (undef, $args) = @_;

    if ($args->{'silent'}) {
        # Sshhhh, be vewy kwiet.
    }
    else {
        # YELL LIKE THERE'S NO TOMORROW!
    }
    my $dbh = Bugzilla->dbh;
    # TODO: Drop the old attachment.status first.
    # populate fielddefs table for attachment status
    my $field = Bugzilla::Field->new({ name => "attachments.$g_a_s"});
    if ($field) {
        $field->set_description('Attachment status');
        $field->set_in_new_bugmail(undef);
        $field->set_buglist(undef);
        $field->_set_type(Bugzilla::Constants::FIELD_TYPE_SINGLE_SELECT);
        $field->set_is_mandatory(undef);
        $field->set_is_numeric(undef);
        $field->update();
    } else {
        # error - failed to install fielddef
    }
    # populate gnome_attachment_status table
    my $table_size = $dbh->selectrow_array("SELECT COUNT(*) FROM $g_a_s");

    unless ($table_size) {
        my $insert = $dbh->prepare("INSERT INTO $g_a_s (value, sortkey) VALUES (?,?)");
        my $sortorder = 0;
        my @values = ('none',
                      'accepted-commit_now',
                      'needs-work',
                      'accepted-commit_after_freeze',
                      'commited',
                      'rejected',
                      'reviewed');
        foreach my $value (@values) {
            $sortorder += 100;
            $insert->execute($value, $sortorder);
        }
    }
}

# Possibly creating AttachmentStatus package is not necessary.
# Something like following should be enough for validation
#    my $object = Bugzilla::Field::Choice->type($g_a_s)->check($value);
#    return $object->name;
#
# But we need to fill the gnome_attachment status table with possible values:
# 1. none
# 2. accepted - commit now (old: accepted-commit_now)
# 3. needs work (old: needs-work)
# 4. accepted - commit after freeze (old: accepted-commit_after_freeze)
# 5. commited
# 6. rejected
# 7. reviewed

sub enabled {
    undef;
}

__PACKAGE__->NAME;
