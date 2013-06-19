package Has::Tiny;

use strict;
use warnings;
no warnings qw(uninitialized once void numeric);

use B qw(perlstring);

our @EXPORT = qw(has);
our %ATTRIBUTES;
our %VALIDATORS;

sub _croak ($;@) { require Type::Exception; goto \&Type::Exception::croak }

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

# curry method call
sub _exporter_expand_sub
{
	my $me = shift;
	my ($name) = @_;
	
	if ($name eq q(has))
	{
		my $real = $me->can("has"); #cheezburger??
		return has => sub { unshift @_, __PACKAGE__; goto $real };
	}
	
	return $me->SUPER::_exporter_expand_sub(@_);
}

sub has
{
	my $me = shift;
	my ($attrs, %options) = @_;
	$attrs = [$attrs] unless ref($attrs) eq q(ARRAY);
	
	my $class = caller;
	delete $VALIDATORS{$class};
	
	my @code = "package $class;";
	for my $a (@$attrs)
	{
		$ATTRIBUTES{$class}{$a} = +{ %options };
		push @code, $me->_build_methods($class, $a, $ATTRIBUTES{$class}{$a});
	}
	my $str = join "\n", @code, "1;";
	
	eval($str) or die("COMPILE ERROR: $@\nCODE:\n$str\n");
	return;
}

sub validate_hashref
{
	my $me = shift;
	my ($class, $hashref) = @_;
	$VALIDATORS{$class} ||= $me->_build_validator($class, $ATTRIBUTES{$class});
	$VALIDATORS{$class}->($hashref);
}

sub _build_methods
{
	my $me = shift;
	my ($class, $attr, $spec) = @_;
	my @code;
	
	if ($spec->{is} eq q(rwp))
	{
		push @code,
			$me->_build_reader($class, $attr, $spec, $attr),
			$me->_build_writer($class, $attr, $spec, "_set_$attr");
	}
	elsif ($spec->{is} eq q(rw))
	{
		push @code, $me->_build_accessor($class, $attr, $spec, $attr);
	}
	else
	{
		push @code, $me->_build_reader($class, $attr, $spec, $attr);
	}
	
	if ($spec->{predicate} eq q(1))
	{
		push @code, $me->_build_predicate($class, $attr, $spec, "has_$attr");
	}
	elsif ($spec->{predicate})
	{
		push @code, $me->_build_predicate($class, $attr, $spec, $spec->{predicate});
	}
	
	return @code;
}

sub _build_reader
{
	my $me = shift;
	my ($class, $attr, $spec, $method) = @_;
	
	my $builder_name;
	if ($spec->{builder} eq q(1))
	{
		$builder_name = "_build_$attr";
	}
	elsif (ref($spec->{builder}) eq q(CODE))
	{
		no strict qw(refs);
		$builder_name = "_build_$attr";
		*{"$class\::$builder_name"} = $spec->{builder};
	}
	elsif ($spec->{builder})
	{
		$builder_name = $spec->{builder};
	}
	
	return $builder_name
		? sprintf('sub %s { $_[0]{%s} ||= $_[0]->%s }', $method, perlstring($attr), $builder_name)
		: sprintf('sub %s { $_[0]{%s}               }', $method, perlstring($attr));
}

sub _build_predicate
{
	my $me = shift;
	my ($class, $attr, $spec, $method) = @_;
	return sprintf('sub %s { exists $_[0]{%s} }', $method, perlstring($attr));
}

sub _build_writer
{
	my $me = shift;
	my ($class, $attr, $spec, $method) = @_;
	
	my $inlined;
	my $isa = $spec->{isa};
	if (blessed($isa) and $isa->can_be_inlined)
	{
		$inlined = $isa->inline_assert('$_[1]');
	}
	elsif ($isa)
	{
		$inlined = sprintf('$Has::Tiny::ATTRIBUTES{%s}{%s}{isa}->($_[1]);', perlstring($class), perlstring($attr));
	}
	
	return defined($inlined)
		? sprintf('sub %s { %s; $_[0]{%s} = $_[1] }', $method, $inlined, perlstring($attr))
		: sprintf('sub %s {     $_[0]{%s} = $_[1] }', $method,           perlstring($attr));
}

sub _build_accessor
{
	my $me = shift;
	my ($class, $attr, $spec, $method) = @_;
	...;
}

sub _build_validator
{
	my $me = shift;
	my ($class, $attributes) = @_;
	...;
}

1;
