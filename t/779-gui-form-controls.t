# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Mojo::DOM;
use Test::Fatal qw(exception);
use lib 't/lib';
use GPForum::Test::GuiForm;
our $VERSION = '0.001';
my $dom = Mojo::DOM->new(
q{<form method="post" action="/publish"><input type="hidden" name="csrf_token" value="actual-token"><input type="checkbox" name="after_publish" value="attachment"><input type="checkbox" name="selected" checked><input name="disabled" disabled value="bad"><fieldset disabled><input name="nested" value="bad"></fieldset><textarea name="body">A &amp; B</textarea><select name="category"><option value="one">One</option><option value="two">Two</option></select><select name="tags" multiple><option selected value="a">A</option><option selected value="b">B</option></select><input name="options" value="first"><input name="options" value="second"><button name="operation" value="publish">Publish</button><button name="operation" value="preview" formaction="/preview">Preview</button></form>}
);
my $form   = $dom->at('form');
my $fields = GPForum::Test::GuiForm->fields($form);
ok( !exists $fields->{after_publish},
    'unchecked media continuation is not submitted' );
ok( !exists $fields->{disabled} && !exists $fields->{nested},
    'disabled controls are not submitted' );
ok( !exists $fields->{operation}, 'unclicked buttons are not submitted' );
is( $fields->{csrf_token}, 'actual-token', 'rendered CSRF is retained' );
is( $fields->{selected}, 'on', 'checked option has the native default value' );
is( $fields->{body},     'A & B', 'text is decoded as a browser submits it' );
is( $fields->{category}, 'one',
    'a single select has its first option by default' );
is_deeply( $fields->{tags}, [ 'a', 'b' ], 'multiple selections are preserved' );
is_deeply(
    $fields->{options},
    [ 'first', 'second' ],
    'duplicate field names are preserved'
);
my $request = GPForum::Test::GuiForm->request(
    $form,
    { body => 'Edited' },
    $dom->at('button[value="preview"]')
);
is( $request->{action}, '/preview',
    'the clicked button selects its actual destination' );
is( $request->{fields}{operation},
    'preview', 'only the clicked operation is submitted' );
like(
    exception { GPForum::Test::GuiForm->request( $form, { invented => 'x' } ) },
    qr/absent[ ]from[ ]the[ ]GUI/msx,
    'a test cannot silently invent a missing control'
);
done_testing();
1;
