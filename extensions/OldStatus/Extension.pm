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

use List::MoreUtils qw(natatime);

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
    my $column = $dbh->bz_column_info(a(), st());

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

sub first_component_of
{
    my ($product) = @_;

    my @components = $product->components;
    # Components returns an array of array refs containing one
    # component or an array with single element being an array ref of
    # components. Possibly a bug, eh? Either way we are interested
    # only in first element of first element anyway.
    die 'product has no components' unless (@components > 0 and @{$components[0]} > 0);
    $components[0][0];
}

sub schema_hash
{
    my $dbh = Bugzilla->dbh;
    my $stmt = $dbh->prepare('SELECT schema_data, version FROM bz_schema') or die $dbh->errstr;

    $stmt->execute or die $stmt->errstr;

    my $row = $stmt->fetchrow_hashref('NAME_lc');

    die $stmt->errstr unless ($row);

    my $VAR1;

    $row->{'schema_data'} = eval ($row->{'schema_data'});
}

sub serialize_schema
{
    my ($schema_data) = @_;

    # Make it ok to eval
    local $Data::Dumper::Purity = 1;

    # Avoid cross-refs
    local $Data::Dumper::Deepcopy = 1;

    # Always sort keys to allow textual compare
    local $Data::Dumper::Sortkeys = 1;

    return Dumper($schema_data);
}

sub store_schema
{
    my ($schema) = @_;
    my $dbh = Bugzilla->dbh;
    my $serialized = serialize_schema($schema->{'schema_data'});
    my $stmt = $dbh->prepare('UPDATE bz_schema ' .
                             'SET schema_data = ?, version = ?') or die $dbh->errstr;

    $stmt->bind_param(1, $serialized, $dbh->BLOB_TYPE);
    $stmt->bind_param(2, $schema->{'version'});
    $stmt->execute() or die $stmt->errstr;
}

sub hack_the_schema
{
    my $schema = schema_hash;

    die 'no attachments fields in schema' unless (exists ($schema->{'schema_data'}{a()}{'FIELDS'}));

    my $fields = $schema->{'schema_data'}{a()}{'FIELDS'};
    my $fields_it = natatime 2, @{$fields};
    my $status_def = undef;

    while (my @name_and_def = $fields_it->())
    {
        next if $name_and_def[0] ne st();
        $status_def = $name_and_def[1];
        last;
    }

    die 'no status field in attachments table' unless ($status_def);
    die 'no foreign key in status field' unless (exists($status_def->{'REFERENCES'}));
    $status_def->{'REFERENCES'}{'created'} = 1;

    store_schema($schema);
}

sub install_before_final_checks
{
    my ($self, $args) = @_;
    my $dbh = Bugzilla->dbh;
    my $column = $dbh->bz_column_info(a(), st());

    return if (defined ($column));

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

    $dbh->bz_start_transaction;
    $dbh->bz_add_column(a(), st(), $definition, 'none');
    $dbh->bz_add_index(a(), 'attachment_index', ['ispatch']);
    $dbh->bz_add_index(a(), a() . '_' . st(), [st()]);
    hack_the_schema;

    my $user = first_user;
    Bugzilla->set_user($user);
    my $product = first_product;
    my $bug = Bugzilla::Bug->create({'product' => $product,
                                     'component' => first_component_of($product)->name,
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

        $attachment->{st()} = $pair->[0];
        $attachment->update;
        ++$counter;
    }

    my $stmt = $dbh->prepare('INSERT INTO namedqueries (userid, name, query) VALUES (?, ?, ?)');

    $stmt->execute($user->id, 'ajwaj', '\'component=TestComponent&f1=' . a() . '.' . st() . '&o1=notequals&query_format=advanced&resolution=---&v1=none&order=bug_status%2Cpriority%2Cassigned_to%2Cbug_id\'') or die $stmt->errstr;
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
