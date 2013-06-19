package Has::Tiny;

use strict;
use warnings;
no warnings qw(uninitialized once void numeric);

use B qw(perlstring);
use Scalar::Util qw(blessed);

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

my $default_buildargs = sub
{
	my $class = shift;
	return +{
		(@_ == 1 && ref($_[0]) eq q(HASH)) ? %{$_[0]} : @_
	};
};

sub create_constructor
{
	my $me = shift;
	my ($method, %options) = @_;
	
	my $class = caller;
	
	my $build     = $options{build};
	my $buildargs = $options{buildargs} || $default_buildargs;
	my @validator = map {
		$VALIDATORS{$_} ||= $me->_compile_validator($_, $ATTRIBUTES{$_});
	} $me->_find_parents($class);
	
	my $code = sub
	{
		my $class = shift;
		my $self = bless($class->$buildargs(@_), $class);
		$_->($self) for @validator;
		$self->$build if $options{build};
		return $self;
	};
	
	no strict qw(refs);
	*{"$class\::$method"} = $code;
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

sub _compile_validator
{
	my $me = shift;
	my $code = join "\n" => (
		"#line 1 \"validator(Has::Tiny)\"",
		"package $_[0];",
		'sub {',
		'my $self = $_[0];',
		$me->_build_validator_parts(@_),
		'return $self;',
		'}',
	);
	eval $code;
}

sub _build_validator_parts
{
	my $me = shift;
	my ($class, $attributes) = @_;
	
	my @code;
	for my $a (sort keys %$attributes)
	{
		my $spec = $attributes->{$a};
		
		if ($spec->{default})
		{
			push @code, sprintf(
				'exists($self->{%s}) or $self->{%s} = $Has::Tiny::ATTRIBUTES{%s}{%s}{default}->();',
				map perlstring($_), $a, $a, $class, $a,
			);
		}
		elsif ($spec->{required})
		{
			push @code, sprintf(
				'exists($self->{%s}) or Has::Tiny::_croak("Attribute %%s is required by %%s", %s, %s);',
				map perlstring($_), $a, $a, $class,
			);
		}
		
		my $isa = $spec->{isa};
		if (blessed($isa) and $isa->can_be_inlined)
		{
			push @code, (
				sprintf('if (exists($self->{%s})) {', $a),
				$isa->inline_assert(sprintf '$self->{%s}', perlstring($a)),
				'}',
			);
		}
		elsif ($isa)
		{
			push @code, (
				sprintf('if (exists($self->{%s})) {', $a),
				sprintf('$Has::Tiny::ATTRIBUTES{%s}{%s}{isa}->($self->{%s});', map perlstring($_), $class, $a, $a),
				'}',
			);
		}
	}
	
	return @code;
}

sub _find_parents
{
	my $me = shift;
	my $class = $_[0];
	
	if (eval { require mro } or eval { require MRO::Compat })
	{
		return @{ mro::get_linear_isa($class) };
	}
	
	require Class::ISA;
	return Class::ISA::self_and_super_path($class);
}

1;


__END__

=pod

=encoding utf-8

=head1 NAME

Has::Tiny - just enough attributes to get by

=head1 SYNOPSIS

   package Person;
   
   use Has::Tiny;
   use Types::Standard -types;
   
   has name => (isa => Str);
   has age  => (isa => Num);
   
   Has::Tiny->create_constructor("new");

=head1 DESCRIPTION

Has::Tiny provides a Moose-like C<has> function. It is not particularly
full-featured, providing just enough to be useful for L<Type::Tiny> and
related modules.

Generally speaking, I'd recommend using L<Moo> or L<Moose> instead.

=head2 Methods

=over

=item C<< has \@attrs, %spec >>

=item C<< has $attr, %spec >>

Create an attribute. This method can also be exported as a usable function.

The specification supports the following options:

=over

=item C<< is => "ro" | "rw" | "rwp" >>

Defaults to "ro".

=item C<< required => 1 >>

=item C<< default => $coderef >>

Defaults are always eager (not lazy).

=item C<< builder => $coderef | $method_name | 1 >>

Builders are always lazy.

=item C<< predicate => $method_name | 1 >>

=item C<< isa => $type >>

=back

=item C<< create_constructor $method_name, %options >>

If you want a constructor, then make sure you call this B<after> defining
your attributes.

Currently supported options:

=over

=item C<< buildargs => $coderef | $method_name >>

=item C<< build => $coderef | $method_name >>

=back

=back

=head1 CAVEATS

Inheriting attributes from parent classes is not super well-tested.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Type-Tiny>.

=head1 SEE ALSO

L<Moo>, L<Moose>, L<Mouse>.

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

