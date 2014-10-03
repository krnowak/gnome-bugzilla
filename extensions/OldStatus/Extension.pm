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

use List::MoreUtils qw(any);

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook"
# in the bugzilla directory) for a list of all available hooks.

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info(a(), 'status');

    unless (defined ($column))
    {
        $dbh->bz_start_transaction;

        my $insert = $dbh->prepare('INSERT INTO ' . a_s() . ' (value, sortkey, description) VALUES (?,?,?)');
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
    $dbh->bz_add_index(a(), a_s(), [st()]);
    $dbh->bz_commit_transaction;
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
