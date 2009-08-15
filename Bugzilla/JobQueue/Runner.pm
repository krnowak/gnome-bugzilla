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
# The Initial Developer of the Original Code is Mozilla Corporation.
# Portions created by the Initial Developer are Copyright (C) 2008
# Mozilla Corporation. All Rights Reserved.
#
# Contributor(s): 
#   Mark Smith <mark@mozilla.com>
#   Max Kanat-Alexander <mkanat@bugzilla.org>

# XXX In order to support Windows, we have to make gd_redirect_output
# use Log4Perl or something instead of calling "logger". We probably
# also need to use Win32::Daemon or something like that to daemonize.

package Bugzilla::JobQueue::Runner;

use strict;
use File::Basename;
use Pod::Usage;

use Bugzilla::Constants;
use Bugzilla::JobQueue;
use Bugzilla::Util qw(get_text);
BEGIN { eval "use base qw(Daemon::Generic)"; }

our $VERSION = BUGZILLA_VERSION;

# The Daemon::Generic docs say that it uses all sorts of
# things from gd_preconfig, but in fact it does not. The
# only thing it uses from gd_preconfig is the "pidfile"
# config parameter.
sub gd_preconfig {
    my $self = shift;

    my $pidfile = $self->{gd_args}{pidfile};
    if (!$pidfile) {
        $pidfile = bz_locations()->{datadir} . '/' . $self->{gd_progname} 
                   . ".pid";
    }
    return (pidfile => $pidfile);
}

# All config other than the pidfile has to be done in gd_getopt
# in order for it to be set up early enough.
sub gd_getopt {
    my $self = shift;

    $self->SUPER::gd_getopt();

    if ($self->{gd_args}{progname}) {
        $self->{gd_progname} = $self->{gd_args}{progname};
    }
    else {
        $self->{gd_progname} = basename($0);
    }

    # There are places that Daemon Generic's new() uses $0 instead of
    # gd_progname, which it really shouldn't, but this hack fixes it.
    $self->{_original_zero} = $0;
    $0 = $self->{gd_progname};
}

sub gd_postconfig {
    my $self = shift;
    # See the hack above in gd_getopt. This just reverses it
    # in case anything else needs the accurate $0.
    $0 = delete $self->{_original_zero};
}

sub gd_more_opt {
    my $self = shift;
    return (
        'pidfile=s' => \$self->{gd_args}{pidfile},
        'n=s'       => \$self->{gd_args}{progname},
    );
}

sub gd_usage {
    pod2usage({ -verbose => 0, -exitval => 'NOEXIT' });
    return 0
}

sub gd_check {
    my $self = shift;

    # Get a count of all the jobs currently in the queue.
    my $jq = Bugzilla->job_queue();
    my @dbs = $jq->bz_databases();
    my $count = 0;
    foreach my $driver (@dbs) {
        $count += $driver->select_one('SELECT COUNT(*) FROM ts_job', []);
    }
    print get_text('job_queue_depth', { count => $count }) . "\n";
}

sub gd_run {
    my $self = shift;

    my $jq = Bugzilla->job_queue();
    $jq->set_verbose($self->{debug});
    foreach my $module (values %{ Bugzilla::JobQueue::JOB_MAP() }) {
        eval "use $module";
        $jq->can_do($module);
    }
    $jq->work;
}

1;

__END__

=head1 NAME

Bugzilla::JobQueue::Runner - A class representing the daemon that runs the
job queue.

=head1 SYNOPSIS

 use Bugzilla::JobQueue::Runner;
 Bugzilla::JobQueue::Runner->new();

=head1 DESCRIPTION

This is a subclass of L<Daemon::Generic> that is used by L<jobqueue>
to run the Bugzilla job queue.
