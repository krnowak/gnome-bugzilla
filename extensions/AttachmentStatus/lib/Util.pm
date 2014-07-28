# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AttachmentStatus::Util;
use strict;
use base qw(Exporter);
our @EXPORT = qw(
    updating
    fresh
    install_gnome_attachment_status
    update_gnome_attachment_status
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::AttachmentStatus::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

# Checks whether we are updating from old attachment status.
sub updating {
    my $dbh = Bugzilla->dbh;
    my $schema = $dbh->_bz_schema();
    my @columns = $schema->get_table_columns('attachment');

    return undef unless (any {$_ eq 'status'} @columns);

    print "updating: status column exists\n";
    my $info = $dbh->bz_column_info('attachment_status', 'id');

    return undef unless defined $info;

    print "updating: attachment status table exists\n";

    1;
}

# Checks whether we have a vanilla instance.
sub fresh {
    my $dbh = Bugzilla->dbh;
    my $schema = $dbh->_bz_schema();
    my @columns = $schema->get_table_columns('attachment');

    return undef if (any {$_ eq 'status'} @columns);
    print "fresh: no status column\n";
    return undef if (any {$_ eq 'gnome_attachment_status'} @columns);
    print "fresh: no gnome attachment status column\n";

    my $info = $dbh->bz_column_info('attachment_status', 'id');

    return undef if defined ($info);
    print "fresh: no attachment status table\n";

    $info = $dbh->bz_column_info('gnome_attachment_status', 'id');

    # gnome attachment status table has to exist now - it was created
    # in db_schema_abstract_schema hook.
    return undef if not defined $info;

    my $value = $dbh->selectrow_arrayref('SELECT COUNT(*) FROM gnome_attachment_status');
    return undef unless defined $value and $value->[0] == 0;

    print "fresh: attachment status table empty\n";
    1;
}

sub get_definition {
    {TYPE => 'varchar(64)',
     NOTNULL => 1,
     REFERENCES => {TABLE => 'gnome_attachment_status',
                    COLUMN => 'value',
                    DELETE => 'CASCADE'}};
}

sub install_gnome_attachment_status {
    my $dbh = Bugzilla->dbh;
    # gnome attachment status table is created in db_schema_abstract_schema hook
    # populate gnome_attachment_status enum table
    my $insert = $dbh->prepare("INSERT INTO gnome_attachment_status (value, sortkey, description) VALUES (?,?,?)");
    my $sortorder = 0;
    my @pairs = (['none', 'Not reviewed or not a patch'],
                 ['accepted - commit now', 'Reviewed and accepted, submitter can commit it immediately'],
                 ['needs work', 'Reviewed, could be accepted provided that submitter does more work'],
                 ['accepted - commit after freeze', 'Reviewed and accepted, submitter can commit it after freeze is lifted'],
                 ['commited', 'Patch is commited'],
                 ['rejected', 'General idea of the patch is rejected'],
                 ['reviewed', 'Patch is reviewed']);
    foreach my $pair (@pairs) {
        $sortorder += 100;
        $insert->execute($pair->[0], $sortorder, $pair->[1]);
    }

    # add column
    $dbh->bz_add_column('attachment', 'gnome_attachment_status', get_definition, 'none');

    # populate fielddefs table for attachment status
    my $field_params = {
        name => 'attachments.gnome_attachment_status',
        description => 'Attachment status',
        type => Bugzilla::Constants::FIELD_TYPE_SINGLE_SELECT
    };
    Bugzilla::Field->create($field_params);
}

sub update_gnome_attachment_status {
    my $dbh = Bugzilla->dbh;
    my $temp_definition = {TYPE => 'varchar(64)',
                           NOTNULL => 1};

    $dbh->bz_alter_column('attachment', 'status', $temp_definition, 'none');

    my $sth1 = $dbh->prepare('UPDATE attachment SET status = ? WHERE status = ?');
    # TODO: Make sure if this table really contains value column.
    my $sth2 = $dbh->prepare('UPDATE attachment_status SET value = ? WHERE value = ?');

    foreach my $name_pair (['accepted-commit_now', 'accepted - commit now'],
                           ['needs-work'], ['needs work'],
                           ['accepted-commit_after_freeze', 'accepted - commit after freeze']) {
        my $old = $name_pair->[0];
        my $new = $name_pair->[1];

        $sth1->execute($new, $old);
        $sth2->execute($new, $old);
    }
    $dbh->bz_rename_column('attachment', 'status', 'gnome_attachment_status');
    $dbh->bz_rename_table('attachment_status', 'gnome_attachment_status');
    $dbh->bz_alter_column('attachment', 'status', get_definition, 'none');
}

1;
