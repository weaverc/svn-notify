package SVN::Notify;

# $Id$

use strict;
$SVN::Notify::VERSION = '2.10';

=head1 Name

SVN::Notify - Subversion activity notification

=head1 Synopsis

Use F<svnnotify> in F<post-commit>:

  svnnotify --repos-path "$1" --revision "$2" \
    --to developers@example.com [options]

  svnnotify --repos-path "$1" --revision "$2" \
    --to-cx-regex i10n@example.com=I10N [options]

Use the class in a custom script:

  use SVN::Notify;

  my $notifier = SVN::Notify->new(%params);
  $notifier->prepare;
  $notifier->execute;

=head1 Description

This class may be used for sending email messages for Subversion repository
activity. There are a number of different modes supported, and SVN::Notify is
fully subclassable, to easily add new functionality. By default, A list of all
the files affected by the commit will be assembled and listed in a single
message. An additional option allows diffs to be calculated for the changes
and either appended to the message or added as an attachment. See the
C<with_diff> and C<attach_diff> options below.

=head1 Usage

To use SVN::Notify, simply add a call to F<svnnotify> to your Subversion
repository's F<post-commit> script. This script lives at the root of the
repository directory; consult the documentation in F<post-commit.tmpl> for
details. Make sure that you specify the complete path to F<svnnotify>, as well
as to F<svnlook> and F<sendmail> in the options passed to F<svnnotify> so that
everything executes properly.

=cut

# Map the svnlook changed codes to nice labels.
my %map = ( U => 'Modified Files',
            A => 'Added Files',
            D => 'Removed Files',
            _ => 'Property Changed');

##############################################################################

=head1 Class Interface

=head2 Constructor

=head3 new

  my $notifier = SVN::Notify->new(%params);

Constructs and returns a new SVN::Notify object. This object is a handle on
the whole process of collecting metadata and content for the commit email and
then sending it. As such, it takes a number of parameters to affect that
process.

Each of these parameters has a corresponding command-line option that can be
passed to F<svnnotify>. The options have the same names as these parameters,
but any underscores you see here should be replaced with dashes when passed to
F<svnnotify>. Each also has a corresponding single-character option. All of
these are documented here.

Supported parameters:

=over

=item repos_path

  svnnotify --repos-path "$PATH"
  svnnotify -p "$PATH"

The path to the Subversion repository. The path is passed as the first
argument when Subversion executes F<post-commit>. So you can simply pass C<$1>
to this parameter if you like. See the documentation in F<post-commit> for
details. Required.

=item revision

  svnnotify --revision "$REV"
  svnnotify -r "$REV"

The revision number for the current commit. The revision number is passed as
the second argument when Subversion executes F<post-commit>. So you can
simply pass C<$2> to this parameter if you like. See the documentation in
F<post-commit> for details. Required.

=item to

  svnnotify --to commiters@example.com
  svnnotify -t commiters@example.com

The address or addresses to which to send the notification email. To specify
multiple addresses, simply put them all into a comma-delimited list suitable
for an SMTP "From" header. This parameter is required unless C<to_regex_map>
is specified.

=item to_regex_map

  svnnotify --to-regex-map translate@example.com=L18N \
            -x legal@example.com=License

This parameter specifies a hash reference of email addresses to regular
expression strings. SVN::Notify will compile the regular expression strings
into regular expression objects, and then send notification messages if and
only if the name of one or more of the directories affected by a commit
matches the regular expression. This is a good way to have a notification
email sent to a particular mail address (or comma-delimited list of addresses)
only for certain parts of the subversion tree. This parameter is required
unless C<to> is specified.

The command-line options, C<--to-regex_map> and C<-x>, can be specified any
number of times, once for each entry in the hash to be passed to C<new()>. The
value passed to the option must be in the form of the key and the value
separated by an equal sign. Consult the L<Getopt::Long> documentation for more
information.

=item from

  svnnotify --from somewhere@example.com
  svnnotify -f elsewhere@example.com

The email address to use in the "From" line of the email. If not specified,
SVN::Notify will use the username from the commit, as returned by C<svnlook
info>.

=item user_domain

  svnnotify --user-domain example.com
  svnnotify -D example.net

A domain name to append to the username for the "From" header of the email.
During a Subversion commit, the username returned by C<svnlook info> is
usually something like a Unix login name. SVN::Notify will use this username
in the email "From" header unless the C<from> parameter is specified. If you
wish to have the username take the form of a real email address, specify a
domain name and SVN::Notify will append C<\@$domain_name> to the username in
order to create a real email address. This can be useful if all of your
committers have an email address that corresponds to their username at the
domain specified by the C<user_domain> parameter.

=item svnlook

  svnnotify --svnlook /path/to/svnlook
  svnnotify --l /path/to/svnlook

The location of the F<svnlook> executable. The default is
F</usr/local/bin/svnlook>. Specify a different path or set the C<$SVNLOOK>
environment variable if this is not the location of F<svnlook> on your
box. It's important to provide a complete path to F<svnlook> because the
environment during the execution of F<post-commit> is anemic, with nary a
C<$PATH> environment variable to be found. So if F<svnnotify> appears not to
be working at all (and Subversion seems loathe to log when it dies!), make
sure that you have specified the complete path to a working F<svnlook>
executable.

=item sendmail

  svnnotify --sendmail /path/to/sendmail
  svnnotify --s /path/to/sendmail

The location of the F<sendmail> executable. The default is
F</usr/sbin/sendmail>. Specify a different path or set the C<$SENDMAIL>
environment variable if this is not the location of F<sendmail> on your box.
The same caveats as applied to the location of the F<svnlook> executable
apply here.

=item charset

  svnnotify --charset UTF-8
  svnnotify -c Big5

The character set typically used on the repository for log messages, file
names, and file contents. Used to specify the character set in the email
Content-Type headers. Defaults to UTF-8.

=item with_diff

  svnnotify --with-diff
  svnnotify -d

A boolean value specifying whether or not to include the output of C<svnlook
diff> in the notification email. The diff will be inline at the end of the
email unless the C<attach_diff> parameter specifies a true value.

=item attach_diff

  svnnotify --attach-diff
  svnnotify -a

A boolean value specifying whether or not to attach the output of C<svnlook
diff> to the notification email. Rather than being inline in the body of the
email, this parameter causes SVN::Notify to attach the diff as a separate
file, named for the user who triggered the commit and the date and time UTC at
which the commit took place. Specifying this parameter to a true value
implicitly sets the C<with_diff> parameter to a true value.

=item reply_to

  svnnotify --reply-to devlist@example.com
  svnnotify --R developers@example.net

The email address to use in the "Reply-To" header of the notification email.
No "Reply-To" header will be added to the email if no value is specified for
the C<reply_to> parameter.

=item subject_prefix

  svnnotify --subject-prefix [Devlist]
  svnnotify -P (Our-Developers)

An optional string to prepend to the beginning of the subject line of the
notification email.

=item subject_cx

  svnnotify --subject-cx
  svnnotify -C

A boolean value indicating whether or not to include a the context of the
commit in the subject line of the email. In a commit that affects multiple
files, the context will be the name of the shortest directory affected by the
commit. This should indicate up to how high up the Subversion repository tree
the commit had an effect. If the commit affects a single file, then the
context will simply be the name of that file.

=item max_sub_length

  svnnotify --max-sub-length 72
  svnnotify -i 76

The maximum length of the notification email subject line. SVN::Notify
includes the first line of the commit log message, or the first sentence of
the message (defined as any text up to the string ". "), whichever is
shorter. This could potentially be quite long. To prevent the subject from
being over a certain number of characters, specify a maximum length here, and
SVN::Notify will truncate the subject to the last word under that length.

=item handler

  svnnotify --handler HTML
  svnnotify -H HTML

Specify the subclass of SVN::Notify to be constructed and returned, and
therefore to handle the notification. Of course you can just use a subclass
directly, but this parameter is designed to make it easy to just use
C<< SVN::Notify->new >> without worrying about loading subclasses, such as
in F<svnnotify>.

=item format

  svnnotify --format text
  svnnotify -A html

The format of the notification email. Two formats are supported, "text" and
"html". If "html" is specified, HTML::Entities B<must> be installed to ensure
that the log message, file names, and diff are properly escaped.

B<Note:> This parameter is deprecated and will be removed in the next release.
Use C<handler>, instead.

=item viewcvs_url

  svnnotify --viewcvs-url http://svn.example.com/viewcvs/
  svnnotify -U http://viewcvs.example.net/

If a URL is specified for this parameter, then it will be used to create a
linnk to the ViewCVS URL corresponding to the current revision number.

=item verbose

  svnnotify --verbose -V

A value between 0 and 3 specifying how verbose SVN::Notify should be. The
default is 0, meaning that SVN::Notify will be silent. A value of 1 causes
SVN::Notify to output some information about what it's doing, while 2 and 3
each cause greater verbosity. To set the verbosity on the command line, simply
pass the C<--verbose> or C<-V> option once for each level of verbosity, up to
three times.

=item boundary

The boundary to use between email body text and attachments. This is normally
generated by SVN::Notify.

=item subject

The subject of the email to be sent. This attribute is normally generated by
C<prepare_subject()>.

=back

=cut

sub new {
    my ($class, %params) = @_;

    # Delegate to a subclass if requested.
    if (my $handler = delete $params{handler}) {
        my $class = __PACKAGE__ . "::$handler";
        eval "require $class" or die $@;
        return $class->new(%params);
    }

    # Check for required parameters.
    $class->_dbpnt( "Checking required parameters to new()")
      if $params{verbose};
    die qq{Missing required "repos_path" parameter}
      unless $params{repos_path};
    die qq{Missing required "revision" parameter}
      unless $params{revision};
    die qq{Missing required "to" or "to_regex_map" parameter}
      unless $params{to} || $params{to_regex_map};

    # Set up default values.
    $params{svnlook}   ||= $ENV{SVNLOOK}  || '/usr/local/bin/svnlook';
    $params{sendmail}  ||= $ENV{SENDMAIL} || '/usr/sbin/sendmail';
    $params{with_diff} ||= $params{attach_diff};
    $params{verbose}   ||= 0;
    $params{charset}   ||= 'UTF-8';

    # Make it so!
    $class->_dbpnt( "Instantiating $class object") if $params{verbose};
    return bless \%params, $class;
}

##############################################################################

=head2 Class Methods

=head3 content_type

  my $content_type = SVN::Notify->content_type;

Returns the content type of the notification message, "text/plain". Used to
set the Content-Type header for the message.

=cut

sub content_type { 'text/plain' }

##############################################################################

=head3 file_label_map

  my $map = SVN::Notify->file_label_map;

Returns a hash reference of the labels to be used for the lists of files. A
hash reference of file lists is stored in the C<files> attribute after
C<prepare_files()> has been called. The hash keys in that list correspond to
Subversion status codes, and these are mapped to their appropriate labels by
the hash reference returned by this method:

  { U => 'Modified Files',
    A => 'Added Files',
    D => 'Removed Files',
    _ => 'Property Changed'
  }

=cut

sub file_label_map { \%map }

##############################################################################

=head1 Instance Interface

=head2 Instance Methods

=head3 prepare

  $notifier->prepare;

Prepares the SVN::Notify object, collecting all the data it needs in
preparation for sending the notification email. Really it's just a shortcut
for:

  $notifier->prepare_recipients;
  $notifier->prepare_contents;
  $notifier->prepare_files;
  $notifier->prepare_subject;

Only it returns after the call to C<prepare_recipients()> if there are no
recipients (that is, as when recipients are specified solely by the
C<to_regex_map> parameter and none of the regular expressions match any of the
affected directories).

=cut

sub prepare {
    my $self = shift;
    $self->prepare_recipients;
    return $self unless $self->{to};
    $self->prepare_contents;
    $self->prepare_files;
    $self->prepare_subject;
}

##############################################################################

=head3 prepare_recipients

  $notifier->prepare_recipients;

Collects and prepares a list of the notification recipients. The recipients
are a combination of the value passed to the C<to> parameter as well as any
email addresses specified as keys in the hash reference passed C<to_regex_map>
parameter, where the regular expressions stored in the values match one or
more of the names of the directories affected by the commit.

If the F<subject_cx> parameter to C<new()> has a true value,
C<prepare_recipients()> also determines the directory name to use for the
context.

=cut

sub prepare_recipients {
    my $self = shift;
    $self->_dbpnt( "Preparing recipients list") if $self->{verbose};
    return $self unless $self->{to_regex_map} || $self->{subject_cx};
    my @to = $self->{to} ? ($self->{to}) : ();
    my $regexen = delete $self->{to_regex_map};
    if ($regexen) {
        $self->_dbpnt( "Compiling regex_map regular expressions")
          if $self->{verbose} > 1;
        for (values %$regexen) {
            $self->_dbpnt( qq{Compiling "$_"}) if $self->{verbose} > 2;
            # Remove initial slash and compile.
            s|^\^[/\\]|^|;
            $_ = qr/$_/;
        }
    } else {
        $regexen = {};
    }

    my ($len, $cx);
    my $fh = $self->_pipe('-|', $self->{svnlook}, 'dirs-changed',
                          $self->{repos_path}, '-r', $self->{revision});

    # Read in a list of the directories changed.
    while (<$fh>) {
        s/[\n\r\/\\]+$//;
        while (my ($email, $rx) = each %$regexen) {
            # If the directory matches the regex, save the email.
            if (/$rx/) {
                $self->_dbpnt( qq{"$_" matched $rx}) if $self->{verbose} > 2;
                push @to, $email;
                delete $regexen->{$email};
            }
        }
        # Grab the context if it's needed for the subject.
        if ($self->{subject_cx}) {
            # XXX Do we need to set utf8 here?
            my $l = length;
            ($len, $cx) = ($l, $_) unless defined $len && $len < $l;
            $self->_dbpnt( qq{Context is "$cx"}) if $self->{verbose} > 1;
        }
    }
    close $fh or warn "Child process exited: $?\n";
    $self->{to} = join ', ', @to;
    $self->{cx} = $cx;
    $self->_dbpnt( qq{Recipients: "$self->{to}"}) if $self->{verbose} > 1;
    return $self;
}

##############################################################################

=head3 prepare_contents

  $notifier->prepare_contents;

Prepares the contents of the commit message, including the name of the user
who triggered the commit (and therefore the contents of the "From" header to
be used in the email) and the log message.

=cut

sub prepare_contents {
    my $self = shift;
    $self->_dbpnt( "Preparing contents") if $self->{verbose};
    my $lines = $self->_read_pipe($self->{svnlook}, 'info', $self->{repos_path},
                                  '-r', $self->{revision});
    $self->{user} = shift @$lines;
    $self->{date} = shift @$lines;
    $self->{message_size} = shift @$lines;
    $self->{message} = $lines;

    # Set up the from address.
    unless ($self->{from}) {
        $self->{from} = $self->{user}
          . ($self->{user_domain} ? "\@$self->{user_domain}" : '');
    }
    if ($self->{verbose} > 1) {
        $self->_dbpnt( "From: $self->{from}");
        $self->_dbpnt( "Message: @$lines");
    }
    return $self;
}

##############################################################################

=head3 prepare_files

  $notifier->prepare_files;

Prepares the lists of files affected by the commit, sorting them into their
categories: modified files, added files, and deleted files. It also compiles a
list of files wherein a property was set, which might have some overlap with
the list of modified files (if a single commit both modified a file and set a
property on it).

If the C<subject_cx> parameter was specified and a single file was affected by
the commit, then C<prepare_files()> will also specify that file name as the
context to be used in the subject line of the commit email.

=cut

sub prepare_files {
    my $self = shift;
    $self->_dbpnt( "Preparing file lists") if $self->{verbose};
    my %files;
    my $fh = $self->_pipe('-|', $self->{svnlook}, 'changed',
                          $self->{repos_path}, '-r', $self->{revision});

    # Read in a list of changed files.
    my $cx = $_ = <$fh>;
    do {
        s/[\n\r]+$//;
        if (s/^(.)(.)\s+//) {
            $self->_dbpnt( "$1 => $_") if $self->{verbose} > 2;
            push @{$files{$1}}, $_;
            push @{$files{_}}, $_ if $2 ne ' ' && $1 ne '_';
        }
    } while (<$fh>);

    if ($self->{subject_cx} && $. == 1) {
        # There's only one file; it's the context.
        $cx =~ s/[\n\r]+$//;
        ($self->{cx} = $cx) =~ s/^..\s+//;
        $self->_dbpnt( qq{File context is "$self->{cx}"})
          if $self->{verbose} > 1;
    }
    # Wait till we get here to close the file handle, otherwise $. gets reset
    # to 0!
    close $fh or warn "Child process exited: $?\n";
    $self->{files} = \%files;
    return $self;
}

##############################################################################

=head3 prepare_subject

  $notifier->prepare_subject;

Prepares the subject line for the notification email. This method B<must> be
called after C<prepare_recipients()> and C<prepare_files()>, since each of
those methods potentially sets up the context for use in the the subject
line. The subject may have a prefix defined by the C<subject_prefix> parameter
to C<new()>, it has the revision number, it might have the context if the
C<subject_cx> specified a true value, and it will have the first sentence or
line of the commit, whichever is shorter. The subject may then be truncated to
the maximum length specified by the C<max_sub_length> parameter.

=cut

sub prepare_subject {
    my $self = shift;
    $self->_dbpnt( "Preparing subject") if $self->{verbose};

    # Start with the optional message and revision number..
    $self->{subject} .=
      (defined $self->{subject_prefix} ?  "$self->{subject_prefix} " : '')
      . "[$self->{revision}] ";

    # Add the context if there is one.
    $self->{subject} .= "$self->{cx}: " if $self->{cx};

    # Truncate to first period after a minimum of 10 characters.
    my $i = index $self->{message}[0], '. ';
    $self->{subject} .= $i > 0
      ? substr($self->{message}[0], 0, $i + 1)
      : $self->{message}[0];

    # Truncate to the last word under 72 characters.
    $self->{subject} =~ s/^(.{0,$self->{max_sub_length}})\s+.*$/$1/m
      if $self->{max_sub_length}
      && length $self->{subject} > $self->{max_sub_length};

    $self->_dbpnt( qq{Subject is "$self->{subject}"}) if $self->{verbose};
    return $self;
}

##############################################################################

=head3 execute

  $notifier->execute;

Sends the notification message. This involves opening a file handle to
F<sendmail> and passing it to C<output()>. This is the main method used to
send notifications or execute any other actions in response to Subversion
activity.

=cut

sub execute {
    my $self = shift;
    $self->_dbpnt( "Sending message") if $self->{verbose};
    return $self unless $self->{to};

    # Safe pipe to sendmail. See perlipc(1).
    my $out = $self->_pipe('|-', $self->{sendmail}, '-oi', '-t');

    # Output the message.
    $self->output($out);

    close $out or warn "Child process exited: $?\n";
    $self->_dbpnt( "Message sent") if $self->{verbose};
    return $self;
}

##############################################################################

=head3 output

  $notifier->output($file_handle);

Called internally by C<execute()> to output a complete email message. The file
handle passed is a piped connection to F<sendmail>, so that C<output()> and
its related methods can print directly to sendmail.

Really C<output()> is a simple wrapper around a number of other method calls.
It is thus essentially a shortcut for:

    $notifier->output_headers($out);
    $notifier->output_content_type($out);
    $notifier->start_body($out);
    $notifier->output_log_message($out);
    $notifier->output_file_lists($out);
    if ($notifier->with_diff) {
        if ($notifier->attach_diff) {
            $notifier->end_body($out);
            $notifier->output_attached_diff($out);
        } else {
            $notifier->output_diff($out);
            $notifier->end_body($out);
        }
    } else {
        $notifier->end_body($out);
    }
    $notifier->end_message($out);

=cut

sub output {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting notification message") if $self->{verbose} > 1;

    $self->output_headers($out);
    $self->output_content_type($out);
    $self->start_body($out);
    $self->output_log_message($out);
    $self->output_file_lists($out);
    if ($self->{with_diff}) {
        if ($self->{attach_diff}) {
            $self->end_body($out);
            $self->output_attached_diff($out);
        } else {
            $self->output_diff($out);
            $self->end_body($out);
        }
    } else {
        $self->end_body($out);
    }
    $self->end_message($out);

    return $self;
}

##############################################################################

=head3 output_headers

  $notifier->output_headers($file_handle);

Outputs the headers for the notification message. If the C<attach_diff>
parameter was set to true, then a boundary string will be generated and the
Content-Type set to "multipart/mixed" and stored as the C<boundary>
attribute.

=cut

sub output_headers {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting headers") if $self->{verbose} > 2;
    print $out
      "MIME-Version: 1.0\n",
      "From: $self->{from}\n",
      "To: $self->{to}\n",
      "Subject: $self->{subject}\n";
    print $out "Reply-To: $self->{reply_to}\n" if $self->{reply_to};
    print $out "X-Mailer: SVN::Notify " . $self->VERSION .
      ": http://search.cpan.org/dist/SVN-Notify/\n";

    # Output the content type.
    if ($self->{attach_diff}) {
        # We need a boundary string.
        unless ($self->{boundary}) {
            my $salt = join '',
              ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
            $self->{boundary} = crypt($self->{subject}, $salt);
        }
        print $out
          qq{Content-Type: multipart/mixed; boundary="$self->{boundary}"\n\n};
    }

    return $self;
}

##############################################################################

=head3 output_content_type

  $notifier->output_content_type($file_handle);

Outputs the content type and transfer encoding headers. These demarcate the
body of the message. This method outputs the content type returned by
C<content_type()>, the character set specified by the C<charset> attribute,
and a Content-Transfer-Encoding of "8bit". Subclasses can either rely on this
functionality or override this method to provide their own content type
headers.

=cut

sub output_content_type {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting content type") if $self->{verbose} > 2;
    my $ctype = $self->content_type;
    print $out "--$self->{boundary}\n" if $self->{attach_diff};
    print $out "Content-Type: $ctype; charset=$self->{charset}\n",
      "Content-Transfer-Encoding: 8bit\n\n";
    return $self;
}

##############################################################################

=head3 start_body

  $notifier->start_body($file_handle);

This method starts the body of the notification message. It outputs the
metadata of the commit, including the revision number, author (user), and date
of the revision. If the C<viewcvs_url> attribute has been set, then the
appropriate URL for the revision will also be output.

=cut

sub start_body {
    my ($self, $out) = @_;
    print $out "\n",
      "Revision: $self->{revision}\n",
      "Author:   $self->{user}\n",
      "Date:     $self->{date}\n";
    print $out
      "ViewCVS:  $self->{viewcvs_url}?rev=$self->{revision}&view=rev\n"
      if $self->{viewcvs_url};
    print $out "\n";

    return $self;
}

##############################################################################

=head3 output_log_message

  $notifier->output_log_message($file_handle);

Outputs the commit log message, as well as the label "Log Message".

=cut

sub output_log_message {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting log message") if $self->{verbose} > 1;
    print $out "Log Message:\n-----------\n",
      join("\n", @{$self->{message}}), "\n";
    return $self;
}

##############################################################################

=head3 output_file_lists

  $notifier->output_log_message($file_handle);

Outputs the lists of modified, added, and deleted files, as well as the list
of files for which properties were changed. The labels used for each group are
pulled in from the C<file_label_map()> class method.

=cut

sub output_file_lists {
    my ($self, $out) = @_;
    my $files = $self->{files} or return $self;
    $self->_dbpnt( "Outputting file lists") if $self->{verbose} > 1;
    my $map = $self->file_label_map;
    # Create the lines that will go underneath the above in the message.
    my %dash = ( map { $_ => '-' x length($map->{$_}) } keys %$map );

    foreach my $type (qw(U A D _)) {
        # Skip it if there's nothing to report.
        next unless $files->{$type};
        $self->_dbpnt( "  Outputting $map->{$type} file list")
          if $self->{verbose} > 2;

        # Identify the action and output each file.
        print $out "\n$map->{$type}:\n$dash{$type}\n";
        print $out "    $_\n" for @{ $files->{$type} };
    }
}

##############################################################################

=head3 end_body

  $notifier->end_body($file_handle);

Closes out the body of the email. Designed to be called when the body of the
message is complete, and before any call to C<output_attached_diff()>.

=cut

sub end_body {
    my ($self, $out) = @_;
    $self->_dbpnt( "Ending body") if $self->{verbose} > 2;
    print $out "\n\n";
    return $self;
}

##############################################################################

=head3 output_diff

  $notifier->output_diff($file_handle);

Sends the output of C<svnlook diff> to the specified file handle for inclusion
in the notification message.

=cut

sub output_diff {
    my ($self, $out) = @_;
    $self->_dbpnt( "Outputting diff") if $self->{verbose} > 1;
    $self->_dump_diff($out);
}

##############################################################################

=head3 output_attached_diff

  $notifier->output_attached_diff($file_handle);

Sends the output of C<svnlook diff> to the specified file handle as an
attachment for inclusion in the notification message.

=cut

sub output_attached_diff {
    my ($self, $out) = @_;
    $self->_dbpnt( "Attaching diff") if $self->{verbose} > 2;
    print $out "\n--$self->{boundary}\n",
      "Content-Disposition: attachment; filename=",
      "r$self->{revision}-$self->{user}.diff\n",
      "Content-Type: text/plain; charset=$self->{charset}\n",
      "Content-Transfer-Encoding: 8bit\n\n";
    $self->_dump_diff($out);
}

##############################################################################

=head3 end_message

  $notifier->end_message($file_handle);

Outputs the final part of the message,. In this case, that means only a
boundary if the C<attach_diff> parameter is true. Designed to be called after
any call to C<output_attached_diff()>.

=cut

sub end_message {
    my ($self, $out) = @_;
    print $out "--$self->{boundary}--\n" if $self->{attach_diff};
    return $self;
}

##############################################################################
# This method actually dumps the output of C<svnlook diff>. It's a separate
# method because output_attached_diff() and output_diff() do essentially the
# same thing, so they can both call it.
##############################################################################

sub _dump_diff {
    my ($self, $out) = @_;
    # Get the diff and output it.
    my $diff = $self->_pipe('-|', $self->{svnlook}, 'diff',
                            $self->{repos_path}, '-r', $self->{revision});

    while (<$diff>) {
        s/[\n\r]+$//;
        print $out "$_\n";
    }
    close $diff or warn "Child process exited: $?\n";
    return $self;
}

##############################################################################

for my $attr (qw(repos_path revision to to_regex_map from user_domain
                 svnlook sendmail charset with_diff attach_diff reply_to
                 subject_prefix subject_cx max_sub_length viewcvs_url
                 verbose boundary user date message message_size subject
                 files)) {
    no strict 'refs';
    *{$attr} = sub {
        my $self = shift;
        return $self->{$attr} unless @_;
        $self->{$attr} = shift;
        return $self;
    };
}

=head2 Accessors

=head3 repos_path

  my $repos_path = $notifier->repos_path;
  $notifier = $notifier->repos_path($repos_path);

Gets or sets the value of the C<repos_path> attribute.

=head3 revision

  my $revision = $notifier->revision;
  $notifier = $notifier->revision($revision);

Gets or sets the value of the C<revision> attribute.

=head3 to

  my $to = $notifier->to;
  $notifier = $notifier->to($to);

Gets or sets the value of the C<to> attribute.

=head3 to_regex_map

  my $to_regex_map = $notifier->to_regex_map;
  $notifier = $notifier->to_regex_map($to_regex_map);

Gets or sets the value of the C<to_regex_map> attribute, which is a hash
reference of email addresses mapped to regular expressions.

=head3 from

  my $from = $notifier->from;
  $notifier = $notifier->from($from);

Gets or sets the value of the C<from> attribute.

=head3 user_domain

  my $user_domain = $notifier->user_domain;
  $notifier = $notifier->user_domain($user_domain);

Gets or sets the value of the C<user_domain> attribute.

=head3 svnlook

  my $svnlook = $notifier->svnlook;
  $notifier = $notifier->svnlook($svnlook);

Gets or sets the value of the C<svnlook> attribute.

=head3 sendmail

  my $sendmail = $notifier->sendmail;
  $notifier = $notifier->sendmail($sendmail);

Gets or sets the value of the C<sendmail> attribute.

=head3 charset

  my $charset = $notifier->charset;
  $notifier = $notifier->charset($charset);

Gets or sets the value of the C<charset> attribute.

=head3 with_diff

  my $with_diff = $notifier->with_diff;
  $notifier = $notifier->with_diff($with_diff);

Gets or sets the value of the C<with_diff> attribute.

=head3 attach_diff

  my $attach_diff = $notifier->attach_diff;
  $notifier = $notifier->attach_diff($attach_diff);

Gets or sets the value of the C<attach_diff> attribute.

=head3 reply_to

  my $reply_to = $notifier->reply_to;
  $notifier = $notifier->reply_to($reply_to);

Gets or sets the value of the C<reply_to> attribute.

=head3 subject_prefix

  my $subject_prefix = $notifier->subject_prefix;
  $notifier = $notifier->subject_prefix($subject_prefix);

Gets or sets the value of the C<subject_prefix> attribute.

=head3 subject_cx

  my $subject_cx = $notifier->subject_cx;
  $notifier = $notifier->subject_cx($subject_cx);

Gets or sets the value of the C<subject_cx> attribute.

=head3 max_sub_length

  my $max_sub_length = $notifier->max_sub_length;
  $notifier = $notifier->max_sub_length($max_sub_length);

Gets or sets the value of the C<max_sub_length> attribute.

=head3 viewcvs_url

  my $viewcvs_url = $notifier->viewcvs_url;
  $notifier = $notifier->viewcvs_url($viewcvs_url);

Gets or sets the value of the C<viewcvs_url> attribute.

=head3 verbose

  my $verbose = $notifier->verbose;
  $notifier = $notifier->verbose($verbose);

Gets or sets the value of the C<verbose> attribute.

=head3 bondary

  my $bondary = $notifier->bondary;
  $notifier = $notifier->bondary($bondary);

Gets or sets the value of the C<bondary> attribute. This string is normally
set by a call to C<output_headers()>, but may be set ahead of time.

=head3 user

  my $user = $notifier->user;
  $notifier = $notifier->user($user);

Gets or sets the value of the C<user> attribute, which is set to the value
pulled in from F<svnlook> by the call to C<prepare_contents()>.

=head3 date

  my $date = $notifier->date;
  $notifier = $notifier->date($date);

Gets or sets the value of the C<date> attribute, which is set to the value
pulled in from F<svnlook> by the call to C<prepare_contents()>.

=head3 message

  my $message = $notifier->message;
  $notifier = $notifier->message($message);

Gets or sets the value of the C<message> attribute, which is set to an array
reference of strings by the call to C<prepare_contents()>.

=head3 message_size

  my $message_size = $notifier->message_size;
  $notifier = $notifier->message_size($message_size);

Gets or sets the value of the C<message_size> attribute, which is set to the
value pulled in from F<svnlook> by the call to C<prepare_contents()>.

=head3 subject

  my $subject = $notifier->subject;
  $notifier = $notifier->subject($subject);

Gets or sets the value of the C<subject> attribute, which is normally set
by a call to C<prepare_subject()>, but may be set explicitly.

=head3 files

  my $files = $notifier->files;
  $notifier = $notifier->files($files);

Gets or sets the value of the C<files> attribute, which is set to a hash
reference of change type mapped to arrays of strings by the call to
C<prepare_files()>.

=cut

##############################################################################
# This method forks off a process to execute an external program and any
# associated arguments and returns a file handle that can be read from to
# fetch the output of the external program, or written to. Pass "-|" as the
# sole argument to read from another process (such as svnlook), and pass "|-"
# to write to another process (such as sendmail).
##############################################################################

sub _pipe {
    my ($self, $mode) = (shift, shift);
    $self->_dbpnt( "Piping execution of '" . join("', '", @_) . "'")
      if $self->{verbose};
    # Safer version of backtick (see perlipc(1)).
    # XXX Use Win32::Process on Win32? This doesn't seem to work as-is on Win32.
    local *PIPE;
    my $pid = open(PIPE, $mode);
    die "Cannot fork: $!\n" unless defined $pid;

    if ($pid) {
        # Parent process. Return the file handle.
        return *PIPE;
    } else {
        # Child process. Execute the commands.
        exec(@_) or die "Cannot exec $_[0]: $!\n";
        # Not reached.
    }
}

##############################################################################
# This method passes its arguments to _pipe(), but then fetches each line
# off output from the returned file handle, safely strips out and replaces any
# newlines and carriage returns, and returns an array reference of those
# lines.
##############################################################################

sub _read_pipe {
    my $self = shift;
    my $fh = $self->_pipe('-|', @_);
    local $/; my @lines = split /[\r\n]+/, <$fh>;
    close $fh or warn "Child process exited: $?\n";
    return \@lines;
}

##############################################################################
# This method is used for debugging output in various verbose modes.
##############################################################################

sub _dbpnt { print __PACKAGE__, ": $_[1]\n" }

1;
__END__

=head2 See Also

=over

=item L<SVN::Notify::HTML|SVN::Notify::HTML>

Subclasses SVN::Notify.

=back

=head1 Bugs

Report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SVN-Notify>.

=head1 To Do

=over

=item *

Port to Win32. I think it just needs to use Win32::Process to manage
communication with F<svnlook> and F<sendmail>. See comments in the source
code.

=back

=head1 Author

David Wheeler <david@kineticode.com>

=head1 Copyright and License

Copyright (c) 2004 Kineticode, Inc. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
