# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::OldStatus;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

# The code for this is in ./extensions/OldStatus/lib/*.pm
use Bugzilla::Extension::OldStatus::Util;
use Bugzilla::Bug;
use Bugzilla::Attachment;

use List::MoreUtils qw(any);

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.

sub status_pairs {
    (['none', 'an unreviewed patch'],
     ['accepted-commit_now', 'The maintainer has given commit permission'],
     ['needs-work', 'The patch needs work'],
     ['accepted-commit_after_freeze', 'This patch is acceptable, but can\'t be committed until after the relevant freeze (string, etc.) is lifted.'],
     ['commited', 'This patch has already been committed but the bug remains open for other reasons'],
     ['rejected', 'The patch provides a change that is just not wanted, or the patch can\'t be fixed to be correct without rewriting.  Maintainers should always explain their reasons whenever marking a patch as rejected.'],
     ['reviewed', 'None of the other states made sense or are quite correct, but the other comments in the bug explain the status of the patch and the patch should be considered to have been reviewed.  If the submitter doesn\'t feel the comments on the patch are clear enough, they can unset this state']);
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info(a(), 'status');

    unless (defined ($column))
    {
        $dbh->bz_start_transaction;

        my $insert = $dbh->prepare('INSERT INTO ' . a_s() . ' (value, sortkey, description) VALUES (?,?,?)');
        my $sortorder = 0;
        foreach my $pair (status_pairs) {
            $sortorder += 100;
            $insert->execute($pair->[0], $sortorder, $pair->[1]);
        }

        my $field_params = {
            name => a_st(),
            description => 'Attachment status',
            type => Bugzilla::Constants::FIELD_TYPE_SINGLE_SELECT
        };
        Bugzilla::Field->create($field_params);

        # attachments table is modified in install_before_final_checks

        $dbh->bz_commit_transaction;
    }
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{'schema'};

    unless (exists ($schema->{a_s()}))
    {
        my $definition = {
              'FIELDS' => [
                            'id',
                            {
                              'NOTNULL' => 1,
                              'PRIMARYKEY' => 1,
                              'TYPE' => 'SMALLSERIAL'
                            },
                            'value',
                            {
                              'NOTNULL' => 1,
                              'TYPE' => 'varchar(64)'
                            },
                            'sortkey',
                            {
                              'DEFAULT' => 0,
                              'NOTNULL' => 1,
                              'TYPE' => 'INT2'
                            },
                            'isactive',
                            {
                              'DEFAULT' => 'TRUE',
                              'NOTNULL' => 1,
                              'TYPE' => 'BOOLEAN'
                            },
                            'visibility_value_id',
                            {
                              'TYPE' => 'INT2'
                            },
                            'description',
                            {
                              'NOTNULL' => 1,
                              'TYPE' => 'MEDIUMTEXT'
                            }
                          ],
              'INDEXES' => [
                             'attachment_status_value_idx',
                             {
                               'FIELDS' => [
                                             'value'
                                           ],
                               'TYPE' => 'UNIQUE'
                             },
                             'attachment_status_sortkey_idx',
                             [
                               'sortkey',
                               'value'
                             ],
                             'attachment_status_visibility_value_id_idx',
                             [
                               'visibility_value_id'
                             ]
                           ]
        };

        $schema->{a_s()} = $definition;
    }
}

sub first_foo
{
    my ($class) = @_;
    my @stuff = $class->get_all;
    die 'no ' . $class . ' instances in db' unless (@stuff > 0);
    $stuff[0];
}

sub first_user
{
    first_foo('Bugzilla::User');
}

sub first_product
{
    first_foo('Bugzilla::Product');
}

sub first_component
{
    first_foo('Bugzilla::Component');
}

sub install_before_final_checks
{
    my ($self, $args) = @_;
    my $silent = $args->{'silent'};
    my $definition = {
        'NOTNULL' => 1,
        'REFERENCES' => {
            'COLUMN' => 'value',
            'DELETE' => 'CASCADE',
            'TABLE' => a_s()
        },
        'TYPE' => 'varchar(64)'
    };
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction;
    $dbh->bz_add_column(a(), st(), $definition, 'none');
    $dbh->bz_add_index(a(), 'attachment_index', ['ispatch']);
    $dbh->bz_add_index(a(), a() . '_' . st(), [st()]);

    my $user = first_user;
    my $bug = Bugzilla::Bug->create({'product' => first_product,
                                     'component' => first_component,
                                     'assigned_to' => $user,
                                     'bug_file_loc' => '',
                                     'bug_severity' => 'enhancement',
                                     'bug_status' => 'CONFIRMED',
                                     'short_desc' => 'blabla',
                                     'op_sys' => 'Linux',
                                     'priority' => '---',
                                     'rep_platform' => 'PC',
                                     'version' => 'unspecified',
                                     'status_whiteboard' => ''});
    my $counter = 1;
    for my $pair (status_pairs) {
        my $attachment = Bugzilla::Attachment->create({'bug' => $bug,
                                                       'data' => "some content\n",
                                                       'description' => 'p' . $counter,
                                                       'filename' => 'p',
                                                       'mimetype' => 'text/plain',
                                                       'ispatch' => 1});

        $attachment->{'status'} = $pair->[0];
        $attachment->update;
        ++$counter;
    }

    my $stmt = $dbh->prepare('INSERT INTO ? (?, ?, ?) VALUES (?, ?, ?)',
                             undef,
                             'namedqueries', 'userid', 'name', 'query',
                             $user->id, 'ajwaj', '\'component=TestComponent&f1=attachments.status&o1=notequals&query_format=advanced&resolution=---&v1=none&order=bug_status%2Cpriority%2Cassigned_to%2Cbug_id\'') or die $dbh->errstr;
    $stmt->execute or die $stmt->errstr;
    $dbh->bz_commit_transaction;
}

sub object_columns {
    my ($self, $args) = @_;
    if ($args->{'class'}->isa(bz_a())) {
        push (@{$args->{'columns'}}, st());
    }
}

# XXX: Gross hack. It would be better if we had a hook (named for
# instance 'object_cgi_update) inside attachment.cgi which provides an
# object being updated and either cgi object or cgi params.
sub cgi_hack_update {
    my ($attachment) = @_;
    my $cgi = Bugzilla->cgi;
    my $status = $cgi->param(st());
    my $action = $cgi->param('action');

    if (defined($status) && defined($action) && $action eq 'update') {
        $attachment->set(st(), $status);
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my $object = $args->{'object'};

    if ($object->isa(bz_a())) {
        push (@{$args->{'columns'}}, st());
        cgi_hack_update($object);
    }
}

sub object_end_of_create_validators {
    my ($self, $args) = @_;

    if ($args->{'class'}->isa(bz_a())) {
        my $params = $args->{'params'};
        # assuming that status, if exists, is already validated
        unless (defined $params->{st()} and $params->{'ispatch'}
                and Bugzilla->user->in_group('editbugs'))
        {
            $params->{st()} = 'none';
        }
    }
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
