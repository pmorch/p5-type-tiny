use v5.14;
use strict;
use warnings;
use Benchmark qw(:hireswallclock timethis);

package Foo {
	use Moo;
}

package Bar {
	use Moo;
	use Types::Standard qw(InstanceOf);
	has attr => (is => 'rw', isa => InstanceOf['Foo']);
}

timethis(5_000, sub {
	my $f = Foo->new;
	my $b = Bar->new(attr => $f);
	$b->attr($f) for 1..100;
});
