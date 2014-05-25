#!/usr/bin/perl -wT

use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::Util qw(i_am_cgi);
use Bugzilla::Version;

use constant ALLOWED_HOSTS => qw(
    209.132.180.167
    209.132.180.178
);

###############
# Subroutines #
###############

sub check_if_version_exists {
    my ($name, $product) = @_;
    my $version = new Bugzilla::Version({ product => $product, name => $name });
    if ($version) {
      print ", exists (", $product->name, ")";
      exit;
    }
}

###############
# Main Script #
###############

Bugzilla->error_mode(ERROR_MODE_DIE);

my $cgi = Bugzilla->cgi;

if (i_am_cgi()) {
    print $cgi->header(-type => 'text/html');

    if (!grep {$_ eq $cgi->remote_addr} ALLOWED_HOSTS) {
        print "Not allowed access from " . $cgi->remote_addr; 
        exit;
    }
}

# We get parameters in a weird way for this script, separated by a |
my ($product_name, $new_version) = split(/\|/, $ENV{'QUERY_STRING'}, 2);

if (!defined($product_name) || !defined($new_version)) {
    print <<END;
Usage: add-version.cgi?product|version
       add-version.pl product version

  product - the bugzilla product with a new version
  version - the new version that has been released

The program calculates what version to add to the database
(e.g. 2.0.x) based on existing versions in that product.
If that doesn't make sense, don't use this script.

For add-version.cgi:

The | in the argument Usage description above is a literal "|", not
an "or" symbol.

This script does not do any un-escaping of CGI query string characters,
so a "+" in the string will be treated as a literal "+"
END
    exit;
}

my $product = Bugzilla::Product::check_product($product_name);

# If the full version already exists, we don't create a .x version.
check_if_version_exists($new_version, $product);

# The version number, but ending in .x instead of its final number.
my $version_x = $new_version;
$version_x =~ s/^([\d\.]+)\.\d+$/$1.x/;

# The version number with explicitly two sets of digits and then ending
# in .x (for example, "2.22" would above become "2.x" but here it would
# become 2.22.x).
my $version_major_minor_x = $new_version;
$version_major_minor_x =~ s/^(\d*?)\.(\d*?)\..*/$1.$2.x/;

# Check if the higher v.x versions exist.
my $last_version_x;
while (1) {
    check_if_version_exists($version_x, $product);
    $last_version_x = $version_x;
    $version_x =~ s/^([\d\.]+)\.\d\.x+$/$1.x/;
    # We go until we get to something like "3.x", which doesn't match the
    # s/// regex, so it'll stay the same and we're done.
    last if $version_x eq $last_version_x;
}

Bugzilla::Version::create($version_major_minor_x, $product);
print ", added";
