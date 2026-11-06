# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::GuiForm;
use v5.40;
use Carp qw(croak);
our $VERSION = '0.001';

# Serialize the actual form, including native successful-control rules. Tests
# must not invent tokens, submit unchecked options or send every submit button.
sub fields ( $class, $form, $submitter = undef ) {
    croak 'GUI form is missing' if !$form;
    my %fields;
    for my $control (
        $form->find('input[name], select[name], textarea[name]')->each )
    {
        next
          if exists $control->attr->{disabled}
          || $control->ancestors('fieldset[disabled]')->size;
        my @values = _values($control);
        _append( \%fields, $control->attr('name'), @values );
    }
    if ( $submitter && defined $submitter->attr('name') ) {
        _append(
            \%fields,
            $submitter->attr('name'),
            $submitter->attr('value') // q{}
        );
    }
    return \%fields;
}

sub request ( $class, $form, $values = {}, $submitter = undef ) {
    my $fields = $class->fields( $form, $submitter );
    for my $name ( keys %{$values} ) {
        my $found = $form->find('[name]')
          ->first( sub { ( $_->attr('name') // q{} ) eq $name } );
        croak "Field $name is absent from the GUI form" if !$found;
        $fields->{$name} = $values->{$name};
    }
    return {
        method => lc(
            ( $submitter ? $submitter->attr('formmethod') : undef )
              // $form->attr('method') // 'get'
        ),
        action => ( $submitter ? $submitter->attr('formaction') : undef )
          // $form->attr('action') // q{},
        fields => $fields,
    };
}

sub _values ($control) {
    return ( $control->text )  if $control->tag eq 'textarea';
    return _selected($control) if $control->tag eq 'select';
    my $type      = lc( $control->attr('type') // 'text' );
    my %non_value = map { $_ => 1 } qw(submit reset image button file);
    return () if $non_value{$type};
    if ( $type eq 'checkbox' || $type eq 'radio' ) {
        return () if !exists $control->attr->{checked};
        return ( $control->attr('value') // 'on' );
    }
    return ( $control->attr('value') // q{} );
}

sub _selected ($control) {
    my @options =
      grep { !exists $_->attr->{disabled} } $control->find('option')->each;
    my @selected = grep { exists $_->attr->{selected} } @options;
    if ( !@selected && !exists $control->attr->{multiple} && @options ) {
        @selected = ( $options[0] );
    }
    return map { $_->attr('value') // $_->text } @selected;
}

sub _append ( $fields, $name, @values ) {
    for my $value (@values) {
        if    ( !exists $fields->{$name} ) { $fields->{$name} = $value; }
        elsif ( ref $fields->{$name} eq 'ARRAY' ) {
            push @{ $fields->{$name} }, $value;
        }
        else { $fields->{$name} = [ $fields->{$name}, $value ]; }
    }
    return;
}
1;
