#!/usr/bin/perl -wT
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
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are Copyright (C) 1998
# Netscape Communications Corporation. All Rights Reserved.
#
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Myk Melez <myk@mozilla.org>
#                 Gervase Markham <gerv@gerv.net>
#                 Dave Lawrence <dkl@redhat.com>

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Browse;
use Bugzilla::Status;

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::Classification;
use Bugzilla::Keyword;
use Bugzilla::Field;

my $user = Bugzilla->login();

my $cgi      = Bugzilla->cgi;
my $dbh      = Bugzilla->dbh;
my $template = Bugzilla->template;
my $vars     = {};

# All pages point to the same part of the documentation.
$vars->{'doc_section'} = 'bugreports.html';

my $product_name = trim($cgi->param('product') || '');
my $product;

if (!$product_name && $cgi->cookie('DEFAULTPRODUCT')) {
    $product_name = $cgi->cookie('DEFAULTPRODUCT');
}

my $product_interests = $user->product_interests();

# If the user didn't select a product and there isn't a default from a cookie,
# try getting the first valid product from their interest list.
if (!$product_name && scalar @$product_interests) {
    foreach my $try (@$product_interests) {
        next if !$user->can_enter_product($try->name);
        $product_name = $try->name;
        last;
    }
}

if ($product_name eq '') {
    # If the user cannot enter bugs in any product, stop here.
    my @enterable_products = @{$user->get_enterable_products};
    ThrowUserError('no_products') unless scalar(@enterable_products);

    my $classification = Bugzilla->params->{'useclassification'} ?
        scalar($cgi->param('classification')) : '__all';

    # Unless a real classification name is given, we sort products
    # by classification.
    my @classifications;

    unless ($classification && $classification ne '__all') {
        if (Bugzilla->params->{'useclassification'}) {
            my $class;
            # Get all classifications with at least one enterable product.
            foreach my $product (@enterable_products) {
                $class->{$product->classification_id}->{'object'} ||=
                    new Bugzilla::Classification($product->classification_id);
                # Nice way to group products per classification, without querying
                # the DB again.
                push(@{$class->{$product->classification_id}->{'products'}}, $product);
            }
            @classifications = sort {$a->{'object'}->sortkey <=> $b->{'object'}->sortkey
                                     || lc($a->{'object'}->name) cmp lc($b->{'object'}->name)}
                                    (values %$class);
        }
        else {
            @classifications = ({object => undef, products => \@enterable_products});
        }
    }

    unless ($classification) {
        # We know there is at least one classification available,
        # else we would have stopped earlier.
        if (scalar(@classifications) > 1) {
            # We only need classification objects.
            $vars->{'classifications'} = [map {$_->{'object'}} @classifications];

            $vars->{'target'} = "browse.cgi";
            $vars->{'format'} = $cgi->param('format');

            print $cgi->header();
            $template->process("global/choose-classification.html.tmpl", $vars)
               || ThrowTemplateError($template->error());
            exit;
        }
        # If we come here, then there is only one classification available.
        $classification = $classifications[0]->{'object'}->name;
    }

    # Keep only enterable products which are in the specified classification.
    if ($classification ne "__all") {
        my $class = new Bugzilla::Classification({'name' => $classification});
        # If the classification doesn't exist, then there is no product in it.
        if ($class) {
            @enterable_products
              = grep {$_->classification_id == $class->id} @enterable_products;
            @classifications = ({object => $class, products => \@enterable_products});
        }
        else {
            @enterable_products = ();
        }
    }

    if (scalar(@enterable_products) == 0) {
        ThrowUserError('no_products');
    }
    elsif (scalar(@enterable_products) > 1) {
        $vars->{'classifications'} = \@classifications;
        $vars->{'target'} = "browse.cgi";
        $vars->{'format'} = $cgi->param('format');

        print $cgi->header();
        $template->process("global/choose-product.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    } else {
        # Only one product exists.
        $product = $enterable_products[0];
    }
}
else {
    # Do not use Bugzilla::Product::check_product() here, else the user
    # could know whether the product doesn't exist or is not accessible.
    $product = new Bugzilla::Product({'name' => $product_name});
}

# We need to check and make sure that the user has permission
# to enter a bug against this product.
$user->can_enter_product($product ? $product->name : $product_name, THROW_ERROR);

# Remember selected product
$cgi->send_cookie(-name => 'DEFAULTPRODUCT',
                  -value => $product->name,
                  -expires => "Fri, 01-Jan-2038 00:00:00 GMT");

# Create data structures representing each classification
my @classifications = (); 
if (scalar @$product_interests) {
    my %watches = ( 
        'name'     => 'Watched Products',
        'products' => $product_interests
    );  
    push @classifications, \%watches;
}

if (Bugzilla->params->{'useclassification'}) {
    foreach my $c (@{$user->get_selectable_classifications}) {
        # Create hash to hold attributes for each classification.
        my %classification = ( 
            'name'       => $c->name, 
            'products'   => [ @{$user->get_selectable_products($c->id)} ]
        );  
        # Assign hash back to classification array.
        push @classifications, \%classification;
    }   
}

$vars->{'classifications'}  = \@classifications;
$vars->{'product'}          = $product;
$vars->{'total_open_bugs'}  = total_open_bugs($product);
$vars->{'what_new_means'}   = what_new_means();
$vars->{'new_bugs'}         = new_bugs($product);
$vars->{'new_patches'}      = new_patches($product);
$vars->{'no_response_bugs'} = scalar(@{no_response_bugs($product)});

my $keyword = Bugzilla::Keyword->new({ name => 'gnome-love' });
if ($keyword) {
    $vars->{'gnome_love_bugs'}  = keyword_bugs($product, $keyword);
}

######################################################################
# Begin temporary searches; If the search will be reused again next
# release cycle, please just comment it out instead of deleting it.
######################################################################

$vars->{'critical_warning_bugs'} = critical_warning_bugs($product);
#$vars->{'string_bugs'} = string_bugs($product);

######################################################################
# End temporary searches
######################################################################

$vars->{'by_patch_status'}    = by_patch_status($product);
$vars->{'buglink'}            = browse_bug_link($product);
$vars->{'by_version'}         = by_version($product);
$vars->{'by_target'}          = by_target($product);
$vars->{'by_priority'}        = by_priority($product);
$vars->{'by_severity'}        = by_severity($product);
$vars->{'by_component'}       = by_component($product);
$vars->{'target_development'} = gnome_target_development();
$vars->{'target_stable'}      = gnome_target_stable();
$vars->{'needinfo_split'}     = needinfo_split($product);

($vars->{'blockers_stable'}, $vars->{'blockers_development'}) = list_blockers($product);

print Bugzilla->cgi->header();

my $format = $template->get_format("browse/main",
                                   scalar $cgi->param('format'),
                                   scalar $cgi->param('ctype'));
 
print $cgi->header($format->{'ctype'});
$template->process($format->{'template'}, $vars)
   || ThrowTemplateError($template->error());

