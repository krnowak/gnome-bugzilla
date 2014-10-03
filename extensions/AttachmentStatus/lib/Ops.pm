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
use Bugzilla::Extension::AttachmentStatus::Field;
use Bugzilla::Extension::AttachmentStatus::Bug;
use Bugzilla::Extension::AttachmentStatus::Attachment;

our @EXPORT = qw(
    updating
    fresh
    install_gnome_attachment_status
    update_gnome_attachment_status
    validate_status
    cgi_hack_update
    update_choice_class_map
    attachment_edit_handler
    attachment_list_handler
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::AttachmentStatus::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

# Checks whether we are updating from old attachment status. This is
# very specific to the setup of GNOME database.
sub updating {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info(a(), 'status');

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
    my $column = $dbh->bz_column_info(a(), 'status');

    return undef if (defined $column);
    print "fresh: no status column\n";

    $column = $dbh->bz_column_info(a(), g_a_s());
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

sub get_g_a_s_definition {
    {TYPE => 'varchar(64)',
     NOTNULL => 1};
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
    $dbh->bz_add_column(a(), g_a_s(), get_g_a_s_definition(), 'none');
    $dbh->bz_add_index(a(), a() . '_' . g_a_s(), [g_a_s()]);

    # populate fielddefs table for attachment status
    my $field_params = {
        name => a_g_a_s(),
        description => 'Attachment status',
        type => Bugzilla::Constants::FIELD_TYPE_SINGLE_SELECT
    };
    Bugzilla::Field->create($field_params);
    $dbh->bz_commit_transaction;
}

# This code is very specific to the setup of GNOME database.
sub update_gnome_attachment_status {
    # What needs to be done here:
    # 'attachments' table:
    # - rename 'status' column to 'gnome_attachment_status' (1)
    # - get rid of foreign key on 'status' column (2)
    # - rename 'attachments_status' index to
    #   'attachments_gnome_attachment_status_idx' (3)
    # - rename 'attachment_index' to 'attachments_ispatch_idx' (4)
    #
    # 'attachment_status' table:
    # - rename it to 'gnome_attachment_status' (5)
    #
    # 'fielddefs' table:
    # - rename 'attachments.status' to
    #   'attachments.gnome_attachments_status' (6)
    #
    # 'namedqueries' table:
    # - replace all uses of 'attachments.status' with
    #   'attachments.gnome_attachment_status' (7)

    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction;
    # We drop the REFERENCES constraint. There should be no such
    # constraints for fields, as they may be altered by admin. We
    # would not like to have some attachments dropped only because we
    # decided to drop a 'reviewed' value deeming it as a duplicate of
    # 'needs-work', right?
    $dbh->bz_alter_column(a(), 'status', get_g_a_s_definition(), 'none'); # (2)
    $dbh->bz_drop_index(a(), 'attachments_status'); # (3)
    $dbh->bz_drop_index(a(), 'attachment_index'); # (4)
    $dbh->bz_rename_column(a(), 'status', g_a_s()); # (1)
    $dbh->bz_add_index(a(), join('_', a(), g_a_s(), 'idx'), [g_a_s()]); # (3)
    $dbh->bz_add_index(a(), join('_', a(), 'ispatch', 'idx'), ['ispatch']); # (4)
    $dbh->bz_rename_table('attachment_status', g_a_s()); # (5)

    # (6)
    my $stmt = $dbh->prepare('UPDATE fielddefs SET name = ? WHERE name = ?',
                             undef,
                             'attachments.status', a_g_a_s()) or die $dbh->errstr;

    $stmt->execute or die $stmt->errstr;
    # (7)
    my $query_rows = $dbh->selectall_arrayref('SELECT id, query ' .
                                              'FROM namedqueries ' .
                                              'WHERE query ' .
                                              'LIKE \'%attachments.status%\'');

    $stmt = $dbh->prepare('UPDATE namedqueries ' .
                          'SET query = ? ' .
                          'WHERE id = ?') or die $dbh->errstr;
    while (my @row = @{$query_rows})
    {
        my $id = $row[0];
        my $query = $row[1];

        $query =~ s/attachments.status/a_g_a_s()/eg;
        $stmt->execute($query, $id) or die $stmt->errstr;
    }
    $dbh->bz_commit_transaction;
}

# Does the attachment status validation
sub validate_status {
    my ($class_or_object, $value, $field) = @_;

    as_dbg('validate status, class (or object): ', $class_or_object, ', value: ', $value, ', field: ', $field);
    if ($class_or_object->isa(bz_a()) && $field eq g_a_s()) {
        as_dbg('    inside ', bz_a(), ' for field: ', $field);
        if (defined ($value)) {
            #my $validated_field = Bugzilla::Extension::AttachmentStatus::Field->check($value);
            my $validated_field = Bugzilla::Field::Choice->type(a_g_a_s())->check($value);
            as_dbg('result: ', $validated_field);

            return $validated_field->name;
        } else {
            return Bugzilla::Extension::AttachmentStatus::Field::new_none;
        }
    }

    return $value;
}

# XXX: Gross hack. It would be better if we had a hook (named for
# instance 'object_cgi_update) inside attachment.cgi which provides an
# object being updated and either cgi object or cgi params.
sub cgi_hack_update {
    my ($attachment) = @_;
    my $cgi = Bugzilla->cgi;
    as_dbg('    cgi: ', $cgi);
    my $status = $cgi->param(g_a_s());
    my $action = $cgi->param('action');

    if (defined($status) && defined($action) && $action eq 'update') {
        $attachment->set_gnome_attachment_status($status);
    }
}

sub update_choice_class_map {
    my $type = 'Bugzilla::Extension::AttachmentStatus::Field';

    unless (exists (Bugzilla::Field::Choice::CLASS_MAP->{$type->FIELD_NAME()})) {
        Bugzilla::Field::Choice::CLASS_MAP->{$type->FIELD_NAME} = $type;
    }
}

sub attachment_edit_handler {
    my ($file, $vars, $context) = @_;
    my $var_name = 'all_' . g_a_s() . '_values';
    my @values = Bugzilla::Field::Choice->type(a_g_a_s())->get_all();

    $vars->set($var_name, \@values);
}

sub attachment_list_handler {
    my ($file, $vars, $context) = @_;
    my $bug_id = $vars->get('bugid');

    if ($bug_id) {
        my $bug = Bugzilla::Bug->new($bug_id);
        my $show_status = $bug->show_gnome_attachment_status();

        $vars->set('show_gnome_attachment_status', $show_status);
    }
}

1;
