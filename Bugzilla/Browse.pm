# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved.
# Portions created by Everything Solved are Copyright (C) 2006 
# Everything Solved. All Rights Reserved.
#
# Contributor(s): Dave Lawrence <dklawren@gmail.com>

package Bugzilla::Browse;

use strict;

use base qw(Exporter);
@Bugzilla::Browse::EXPORT = qw(
    total_open_bugs
    what_new_means
    new_bugs
    new_patches
    keyword_bugs
    no_response_bugs
    critical_warning_bugs
    string_bugs
    by_patch_status
    by_version
    needinfo_split
    by_target
    by_priority
    by_severity
    by_component
    by_assignee
    gnome_target_development 
    gnome_target_stable
    list_blockers
    browse_bug_link
);

use Bugzilla::User;
use Bugzilla::Search;
use Bugzilla::Field;
use Bugzilla::Status;
use Bugzilla::Util;
use Bugzilla::Install::Util qw(vers_cmp);

use constant IMPORTANT_PATCH_STATUSES => qw(
    none
    accepted-commit_now
    accepted-commit_after_freeze
);

sub browse_open_states {
    my $dbh = Bugzilla->dbh;
    return join(",", map { $dbh->quote($_) } grep($_ ne "NEEDINFO", BUG_STATE_OPEN));
}

sub total_open_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bug_id) 
                                    FROM bugs 
                                   WHERE bug_status IN (" . browse_open_states() . ") 
                                         AND product_id = ?", undef, $product->id);
}

sub what_new_means {
    my $dbh = Bugzilla->dbh;
    return $dbh->selectrow_array("SELECT NOW() - " . $dbh->sql_interval(7, 'DAY'));
}

sub new_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bug_id) 
                                    FROM bugs 
                                   WHERE bug_status IN (" . browse_open_states() . ") 
                                         AND creation_ts >= NOW() - " . $dbh->sql_interval(7, 'DAY') . " 
                                         AND product_id = ?", undef, $product->id);
}

sub new_patches {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(attach_id) 
                                    FROM bugs, attachments 
                                   WHERE bugs.bug_id = attachments.bug_id
                                         AND bug_status IN (" . browse_open_states() . ") 
                                         AND attachments.ispatch = 1 AND attachments.isobsolete = 0
                                         AND attachments.status = 'none' 
                                         AND attachments.creation_ts >= NOW() - " . $dbh->sql_interval(7, 'DAY') . " 
                                         AND product_id = ?", undef, $product->id);
}

sub keyword_bugs {
    my ($product, $keyword) = @_;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bugs.bug_id) 
                                    FROM bugs, keywords 
                                   WHERE bugs.bug_id = keywords.bug_id 
                                         AND bug_status IN (" . browse_open_states() . ") 
                                         AND keywords.keywordid = ? 
                                         AND product_id = ?", undef, ($keyword->id, $product->id));
}

sub no_response_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;
    my @developer_ids = map { $_->id } @{$product->developers};

    if (@developer_ids) {
        return $dbh->selectcol_arrayref("SELECT bugs.bug_id
                                           FROM bugs INNER JOIN longdescs ON longdescs.bug_id = bugs.bug_id 
                                          WHERE bug_status IN (" . browse_open_states() . ") 
                                                AND bug_severity != 'enhancement' 
                                                AND product_id = ? 
                                                AND bugs.reporter NOT IN (" . join(",", @developer_ids) . ") 
                                          GROUP BY bugs.bug_id 
                                         HAVING COUNT(distinct longdescs.who) = 1", undef, $product->id);
    }
    else {
        return [];
    }
}

sub critical_warning_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;
 
    return $dbh->selectrow_array("SELECT COUNT(bugs.bug_id) 
                                    FROM bugs INNER JOIN bugs_fulltext ON bugs_fulltext.bug_id = bugs.bug_id 
                                   WHERE bug_status IN (" . browse_open_states() . ") 
                                         AND " . $dbh->sql_fulltext_search("bugs_fulltext.comments_noprivate", "'+G_LOG_LEVEL_CRITICAL'") . " 
                                         AND product_id = ?", undef, $product->id);
}

sub string_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;
    
    return $dbh->selectrow_array("SELECT COUNT(bugs.bug_id) 
                                    FROM bugs, keywords, keyworddefs 
                                   WHERE bugs.bug_id = keywords.bug_id 
                                         AND keywords.keywordid = keyworddefs.id 
                                         AND keyworddefs.name = 'string' 
                                         AND bug_status IN (" . browse_open_states() . ") 
                                         AND product_id = ?", undef, $product->id);
}

sub by_patch_status {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectall_arrayref("SELECT attachments.status, COUNT(attach_id) 
                                       FROM bugs, attachments
                                      WHERE attachments.bug_id = bugs.bug_id 
                                            AND bug_status IN (" . browse_open_states() . ") 
                                            AND product_id = ? 
                                            AND attachments.ispatch = 1 
                                            AND attachments.isobsolete != 1 
                                            AND attachments.status IN (" . join(",", map { $dbh->quote($_) } IMPORTANT_PATCH_STATUSES) . ") 
                                            GROUP BY attachments.status", undef, $product->id);
}

sub browse_bug_link {
    my $product = shift;
    
    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . 
           join('' ,map { '&bug_status=' . url_quote($_) } grep ($_ ne "NEEDINFO", BUG_STATE_OPEN));
}

sub by_version {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my @result = sort { vers_cmp($a->[0], $b->[0]) } 
        @{$dbh->selectall_arrayref("SELECT version, COUNT(bug_id) 
                                      FROM bugs 
                                     WHERE bug_status IN (" . browse_open_states() . ") 
                                           AND product_id = ? 
                                     GROUP BY version", undef, $product->id)};
    
    return \@result;
}

sub needinfo_split {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my $ni_a = Bugzilla::Search::SqlifyDate('-2w');
    my $ni_b = Bugzilla::Search::SqlifyDate('-4w');
    my $ni_c = Bugzilla::Search::SqlifyDate('-3m');
    my $ni_d = Bugzilla::Search::SqlifyDate('-6m');
    my $ni_e = Bugzilla::Search::SqlifyDate('-1y');
    my $needinfo_case = "CASE WHEN delta_ts < '$ni_e' THEN 'F'
                              WHEN delta_ts < '$ni_d' THEN 'E'
                              WHEN delta_ts < '$ni_c' THEN 'D'
                              WHEN delta_ts < '$ni_b' THEN 'C'
                              WHEN delta_ts < '$ni_a' THEN 'B'
                              ELSE 'A' END";

    my %results = @{$dbh->selectcol_arrayref("SELECT $needinfo_case age, COUNT(bug_id) 
                                       FROM bugs 
                                      WHERE bug_status = 'NEEDINFO' 
                                            AND product_id = ? 
                                      GROUP BY $needinfo_case", { Columns=>[1,2] }, $product->id)};
    return \%results;
}

sub by_target {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my @result = sort { vers_cmp($a->[0], $b->[0]) } 
        @{$dbh->selectall_arrayref("SELECT target_milestone, COUNT(bug_id) 
                                      FROM bugs 
                                     WHERE bug_status IN (" . browse_open_states() . ") 
                                           AND target_milestone != '---' 
                                           AND product_id = ? 
                                     GROUP BY target_milestone", undef, $product->id)};
    
    return \@result;
}

sub by_priority {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my $i = 0;
    my %order_priority = map { $_ => $i++  } @{get_legal_field_values('priority')};
    
    my @result = sort { $order_priority{$a->[0]} <=> $order_priority{$b->[0]} } 
        @{$dbh->selectall_arrayref("SELECT priority, COUNT(bug_id) 
                                      FROM bugs 
                                     WHERE bug_status IN (" . browse_open_states() . ") 
                                           AND product_id = ? 
                                     GROUP BY priority", undef, $product->id)};

    return \@result;
}

sub by_severity {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my $i = 0;
    my %order_severity = map { $_ => $i++  } @{get_legal_field_values('bug_severity')};

    my @result = sort { $order_severity{$a->[0]} <=> $order_severity{$b->[0]} } 
        @{$dbh->selectall_arrayref("SELECT bug_severity, COUNT(bug_id) 
                                      FROM bugs 
                                     WHERE bug_status IN (" . browse_open_states() . ") 
                                           AND product_id = ? 
                                     GROUP BY bug_severity", undef, $product->id)};

    return \@result;
}

sub by_component {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectall_arrayref("SELECT components.name, COUNT(bugs.bug_id) 
                                       FROM bugs INNER JOIN components ON bugs.component_id = components.id 
                                      WHERE bug_status IN (" . browse_open_states() . ") 
                                            AND bugs.product_id = ? 
                                      GROUP BY components.name", undef, $product->id);
}

sub by_assignee {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my @result = map { Bugzilla::User->new($_) } 
        @{$dbh->selectall_arrayref("SELECT bugs.assignee AS userid, COUNT(bugs.bug_id) 
                                      FROM bugs 
                                     WHERE bug_status IN (" . browse_open_states() . ") 
                                           AND bugs.product_id = ? 
                                     GROUP BY components.name", undef, $product->id)};
    
    return \@result;
}

sub gnome_target_development { 
    my @legal_gnome_target = @{get_legal_field_values('cf_gnome_target')};
    return $legal_gnome_target[(scalar @legal_gnome_target) -1];
}

sub gnome_target_stable {
    my @legal_gnome_target = @{get_legal_field_values('cf_gnome_target')};
    return $legal_gnome_target[(scalar @legal_gnome_target) -2];
}

sub list_blockers {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("SELECT bugs.bug_id, products.name AS product, bugs.bug_status, 
                                        bugs.resolution, bugs.bug_severity, bugs.short_desc 
                                   FROM bugs INNER JOIN products ON bugs.product_id = products.id
                                  WHERE product_id = ? 
                                        AND bugs.cf_gnome_target = ? 
                                        AND bug_status IN (" . browse_open_states() . ") 
                                  ORDER BY bug_id DESC");

    my @list_blockers_development;
    $sth->execute($product->id, gnome_target_development());
    while (my $bug = $sth->fetchrow_hashref) {
        push(@list_blockers_development, $bug);
    }
    
    my @list_blockers_stable;
    $sth->execute($product->id, gnome_target_stable());
    while (my $bug = $sth->fetchrow_hashref) {
        push(@list_blockers_stable, $bug);
    }
    
    return (\@list_blockers_stable, \@list_blockers_development);
}

1;
