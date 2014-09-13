# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AttachmentStatus::Ops;
use strict;
use warnings;
use base qw(Exporter);
use Data::Dumper;
use Bugzilla::Extension::AttachmentStatus::Util;

our @EXPORT = qw(
    updating
    fresh
    install_gnome_attachment_status
    update_gnome_attachment_status
    validate_status
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::AttachmentStatus::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

# Checks whether we are updating from old attachment status.
sub updating {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info('attachments', 'status');

    return undef unless (defined $column);
    print "updating: status column exists\n";

    $column = $dbh->bz_column_info('attachment_status', 'id');
    return undef unless defined $column;
    print "updating: attachment status table exists\n";
    print "updating: it is an update\n";
    1;
}

# Checks whether we have a vanilla instance.
sub fresh {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info('attachments', 'status');

    return undef if (defined $column);
    print "fresh: no status column\n";

    $column = $dbh->bz_column_info('attachments', g_a_s());
    return undef if (defined $column);
    print "fresh: no gnome attachment status column\n";

    $column = $dbh->bz_column_info('attachment_status', 'id');
    return undef if defined ($column);
    print "fresh: no attachment status table\n";

    $column = $dbh->bz_column_info(g_a_s(), 'id');
    # gnome attachment status table has to exist now - it was created
    # in db_schema_abstract_schema hook.
    return undef if not defined $column;
    print "fresh: gnome attachment status exists\n";

    my $value = $dbh->selectrow_arrayref('SELECT COUNT(*) FROM ' . g_a_s());
    return undef unless defined $value and $value->[0] == 0;

    print "fresh: gnome attachment status table empty\n";
    print "fresh: it is a fresh install\n";
    1;
}

sub get_definition {
    {TYPE => 'varchar(64)',
     NOTNULL => 1};
# TODO: Looking at bugs.resolution I suppose that
# attachments.(gnome_attachment_)status column has no REFERENCES. I'll
# be sure once I get the attachments table structure. Also, I'm
# getting some errors during checksetup because of it.
#    {TYPE => 'varchar(64)',
#     NOTNULL => 1,
#     REFERENCES => {TABLE => 'gnome_attachment_status',
#                    COLUMN => 'value',
#                    DELETE => 'CASCADE'}};
}

sub install_gnome_attachment_status {
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction;

    # gnome attachment status table is created in db_schema_abstract_schema hook
    # populate gnome_attachment_status enum table
    my $insert = $dbh->prepare('INSERT INTO ' . g_a_s() . ' (value, sortkey, description) VALUES (?,?,?)');
    my $sortorder = 0;
    my @pairs = (['none', 'an unreviewed patch'],
                 ['accepted-commit_now', 'The maintainer has given commit permission'],
                 ['needs-work', 'The patch needs work'],
                 ['accepted-commit_after_freeze', 'This patch is acceptable, but can\'t be committed until after the relevant freeze (string, etc.) is lifted.'],
                 ['commited', 'This patch has already been committed but the bug remains open for other reasons'],
                 ['rejected', 'The patch provides a change that is just not wanted, or the patch can\'t be fixed to be correct without rewriting.  Maintainers should always explain their reasons whenever marking a patch as rejected.'],
                 ['reviewed', 'None of the other states made sense or are quite correct, but the other comments in the bug explain the status of the patch and the patch should be considered to have been reviewed.  If the submitter doesn\'t feel the comments on the patch are clear enough, they can unset this state']);
    foreach my $pair (@pairs) {
        $sortorder += 100;
        $insert->execute($pair->[0], $sortorder, $pair->[1]);
    }

    # add column
    $dbh->bz_add_column('attachments', g_a_s(), get_definition, 'none');

    # populate fielddefs table for attachment status
    my $field_params = {
        name => a_g_a_s(),
        description => 'Attachment status',
        type => Bugzilla::Constants::FIELD_TYPE_SINGLE_SELECT
    };
    Bugzilla::Field->create($field_params);
    $dbh->bz_commit_transaction;
}

sub update_gnome_attachment_status {
    my $dbh = Bugzilla->dbh;
    # TODO: Probably not needed, see comment in get_definition
    # my $temp_definition = {TYPE => 'varchar(64)',
    #                        NOTNULL => 1};

    # TODO: recreate indices!
    $dbh->bz_start_transaction;
    # $dbh->bz_alter_column('attachments', 'status', $temp_definition, 'none');
    $dbh->bz_rename_column('attachments', 'status', g_a_s());
    $dbh->bz_rename_table('attachment_status', g_a_s());
    # $dbh->bz_alter_column('attachments', 'status', get_definition, 'none');

    $dbh->bz_commit_transaction;
}

# Does the attachment status validation
sub validate_status {
    my ($class_or_object, $value, $field) = @_;

    as_dbg('validate status, class (or object): ', $class_or_object, ', value: ', $value, ', field: ', $field);
    if ($class_or_object->isa(bz_a()) && $field eq g_a_s()) {
        as_dbg('    inside ', bz_a(), ' for field: ', $field);
        if (defined ($value)) {
            my $validated_field = Bugzilla::Extension::AttachmentStatus::Field->check($value);
            as_dbg('result: ', $validated_field);

            return $validated_field->name;
        } else {
            return Bugzilla::Extension::AttachmentStatus::Field::create_none;
        }
    }

    return $value;
}

1;
