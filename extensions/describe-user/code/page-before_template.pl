use strict;
use warnings;
use Bugzilla;
use DescribeUser::Hooks;

page(%{ Bugzilla->hook_args });

