package Eval::TypeTiny;

use strict;
use warnings;

sub _clean_eval
{
	no warnings;
	local $@;
	local $SIG{__DIE__};
	my $r = eval $_[0];
	my $e = $@;
	return ($r, $e);
}

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.005_01';
our @EXPORT    = qw( eval_closure );

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

sub import
{
	# do the shuffle!
	no warnings "redefine";
	our @ISA = qw( Exporter::TypeTiny );
	require Exporter::TypeTiny;
	my $next = \&Exporter::TypeTiny::import;
	*import = $next;
	goto $next;
}

my $sandbox = 0;
sub eval_closure
{
	$sandbox++;
	
	my (%args) = @_;
	$args{line}   = 1 unless defined $args{line};
	$args{description} =~ s/[^\w .:-\[\]\(\)\{\}\']//g if defined $args{description};
	$args{source} = qq{#line $args{line} "$args{description}"\n} . $args{source}
		if defined $args{description} && !($^P & 0x10);
	$args{environment} ||= {};
	
	for my $k (sort keys %{$args{environment}})
	{
		next if $k =~ /^\$/ && ref($args{environment}{$k}) =~ /^(SCALAR|REF)$/;
		next if $k =~ /^\@/ && ref($args{environment}{$k}) eq q(ARRAY);
		next if $k =~ /^\%/ && ref($args{environment}{$k}) eq q(HASH);
		_croak "Expected a variable name and ref; got $k => $args{environment}{$k}";
	}
	
	my @keys      = sort keys %{$args{environment}};
	my $i         = 0;
	my $source    = join "\n" => (
		"package Eval::TypeTiny::Sandbox$sandbox;",
		"sub {",
		map(sprintf('my %s = %s{$_[%d]};', $_, substr($_, 0, 1), $i++), @keys),
		$args{source},
		"}",
	);
	
	my ($compiler, $e) = _clean_eval($source);
	_croak "Failed to compile source because: $e\n\nSOURCE: $source" if $e;
	
	return $compiler->(@{$args{environment}}{@keys});
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Eval::TypeTiny - utility to evaluate a string of Perl code in a clean environment

=head1 DESCRIPTION

This is not considered part of Type::Tiny's public API.

It exports one function, which works much like the similarly named function
from L<Eval::Closure>:

=over

=item C<< eval_closure(source => $source, environment => \%env, %opt) >>

=back

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Type-Tiny>.

=head1 SEE ALSO

L<Eval::Closure>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

