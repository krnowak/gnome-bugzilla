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
# The Original Code is the Bugzilla BugBuddy Plugin.
#
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by Canonical Ltd. are Copyright (C) 2009
# Canonical Ltd. All Rights Reserved.
#
# Contributor(s): Bradley Baetz <bbaetz@acm.org>

package extensions::bugbuddy::lib::WSBugBuddy;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

# We have this, so use it rather than requiring another module
use Bugzilla::Install::Util qw(vers_cmp);

use Bugzilla::Auth::Verify::Stack;
use Bugzilla::BugMail;
use Bugzilla::Constants qw(ERROR_MODE_BUGBUDDY);
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Mailer;
use Bugzilla::Token;

# Alias for compat
BEGIN { *Add = \&createBug; }

# Based on gnome 2.20 customisations
sub createBug {
    my ($self, $params) = @_;

    # BugBuddy errors are handled slightly differently
    Bugzilla->error_mode(ERROR_MODE_BUGBUDDY);

    my $given_gnome_version = $params->{'gnome_version'};
    if (!defined($given_gnome_version)) {
        my $cgi = Bugzilla->cgi;
        if ($cgi->user_agent() =~ /^Bug-Buddy: ([0-9]+\.[0-9]+[0-9.]+)$/) {
            $given_gnome_version = $1;
        }
    }
    if (defined($given_gnome_version)
        && vers_cmp($given_gnome_version,
                    Bugzilla->params->{'bugbuddy_min_version'}) == -1)
    {
        ThrowUserError("please_try_with_newer_gnome");
    }

    my $reporter = $params->{reporter};
    my $user = Bugzilla::User->new({ name => $reporter });
    if (!$user) {
        # New user - create an account
        # This implicitly requires that the auth mechanism is the DB.
        # The code itself is generic to any auth method, but we only add the
        # user to the Bugzilla DB, without checking if its present in the
        # external system first. Also, the logic assumes that that's
        # where auth is done, and therefore that we can change the password
        # later

        $reporter = Bugzilla::User->check_login_name_for_creation($reporter);

        # You might assume that a method called 'check_...for_creation'
        # would check to see if the address meets the requirements for
        # an account to be created, but you'd be wrong...
        my $createexp = Bugzilla->params->{'createemailregexp'};
        ThrowUserError('invalid_username') if ($reporter !~ /$createexp/);

        # Rather than sending a password in plain text, issue an expiring
        # one-time token.
        # After that has expired, the user can still go through the normal
        # password reset process
        # If we had a way of enforcing a password change on login that
        # would be much better/simpler, but we don't.
        $user = Bugzilla::User->create({
            login_name    => $reporter,
            cryptpassword => '*',
        });

        my ($token, $expiration_ts) =
            Bugzilla::Token::GeneratePasswordToken($user);

        my $message;
        my $template = Bugzilla->template;
        $template->process('email/bug-buddy-account-created.txt.tmpl',
                           { account       => $reporter,
                             token         => $token,
                             expiration_ts => $expiration_ts,
                             timezone      => $user->timezone }, \$message)
          || ThrowTemplateError($template->error);
        MessageToMTA($message);
    } elsif ($params->{password}) {
        # Auth, but don't set a cookie
        # bug-buddy doesn't currently send a password. When it does, this
        # could later be changed to require a password

        my $auth = Bugzilla::Auth::Verify::Stack->new(Bugzilla->params->{'user_verify_class'});
        my $login_info = $auth->check_credentials({username => $reporter,
                                                   password => $params->{password}});
        if ($login_info->{failure}) {
            Bugzilla::Error::ThrowUserError("invalid_username_or_password");
        }
    }

    if ($user->is_disabled) {
        ThrowUserError('account_disabled');
    }

    Bugzilla->set_user($user);

    # Map XMLRPC params onto what Bugzilla::Bug wants

    # Stuff to copy directly (if present; let ->create handle
    # defaults for stuff not supplied)
    my @bug_fields = qw(
        product component
        short_desc comment
        priority bug_severity
        bug_file_loc status_whiteboard
    );

    my $bug_params = {};
    foreach my $f (@bug_fields) {
        $bug_params->{$f} = $params->{$f}
            if exists $params->{$f};
    }
    if (!$bug_params->{op_sys}) {
        my $op_syses = get_legal_field_values('op_sys');
        $bug_params->{op_sys} = $op_syses->[0];
    }

    # Force nautilus-cd-burner -> nautilus, see bug 352989
    if (lc($params->{product}) eq "nautilus-cd-burner") {
        $bug_params->{product} = 'nautilus';
        $bug_params->{component} = 'general';
    }

    $bug_params->{bug_status} = 'UNCONFIRMED';

    # The gnome versions in the database are like:
    #       2.1/2.2
    #   or: 2.0
    # so we need to parse it out and match against the valid field values
    if ($given_gnome_version =~ /^([0-9]+\.[0-9]+)[. ]/) {
        my $match = $1;
        my $legal_versions = get_legal_field_values('cf_gnome_version');

        my @matches;
        if (@matches = grep($_ =~ /(?:^|\/)\Q$match\E(?:\/|$)/,
                            @$legal_versions)) {
            $bug_params->{cf_gnome_version} = $matches[0];
        }
    }

    # Parse version
    my $prod = Bugzilla::Product->new({'name' => $params->{product}});
    ThrowUserError('product_doesnt_exist') unless $prod;
    # Parse component (need to give a specific error message back)
    grep { $_->name eq $params->{component} } @{$prod->components}
        or ThrowUserError('component_doesnt_exist');

    my $err = "";

    my $versions = $prod->versions;
    if (@$versions) {
        my $version_x = $params->{version};
        $version_x =~ s/^([\d\.]+\.)\d+$/$1x/;

        my @version;
        if (@version = grep(lc($_->name) eq lc($params->{version}),
                            @$versions)) {
            $bug_params->{'version'} = $version[0]->name;
        } elsif ($params->{version} =~ /^[\d\.]+\d+$/) {
            if (@version = grep(/^$version_x$/i,
                                map { $_->name } @$versions)) {
              # We were able to match when the last number was replaced
              # with an 'x' e.g. '1.2.x' instead of '1.2.3'
              $err .= "Version: " . $params->{version} . "\n";
              $bug_params->{'version'} = $version[0]; 
            }
        }
    }
    if (!exists $bug_params->{'version'} && @$versions) {
        $err .= "Version: " . $params->{'version'} . "\n";
        $bug_params->{'version'} = $versions->[0]->name;
    }
    
    # XXX - trace parsing goes here

    $bug_params->{comment} = $err . "\n" . $bug_params->{comment}
        if $err;

    my $bug = Bugzilla::Bug->create($bug_params);

    Bugzilla::BugMail::Send($bug->bug_id, { changer => $bug->reporter->login });
    
    return $bug->bug_id;
}

1;
