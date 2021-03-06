# --
# Kernel/System/DynamicField/Backend/TextArea.pm - Delegate for DynamicField TextArea backend
# Copyright (C) 2001-2012 OTRS AG, http://otrs.org/
# --
# $Id: TextArea.pm,v 1.48.2.4 2012/05/07 21:43:10 cr Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::DynamicField::Backend::TextAreaFromDB;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::System::DynamicFieldValue;
use Kernel::System::DynamicField::Backend::BackendCommon;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.48.2.4 $) [1];

=head1 NAME

Kernel::System::DynamicField::Backend::TextArea

=head1 SYNOPSIS

DynamicFields TextArea backend delegate

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=over 4

=item new()

usually, you want to create an instance of this
by using Kernel::System::DynamicField::Backend->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    for my $Needed (qw(ConfigObject EncodeObject LogObject MainObject DBObject)) {
        die "Got no $Needed!" if !$Param{$Needed};

        $Self->{$Needed} = $Param{$Needed};
    }

    # create additional objects
    $Self->{DynamicFieldValueObject} = Kernel::System::DynamicFieldValue->new( %{$Self} );
    $Self->{BackendCommonObject}
        = Kernel::System::DynamicField::Backend::BackendCommon->new( %{$Self} );

    $Self->{CacheObject} = Kernel::System::Cache->new(%Param);

    # set the maximum lenght for the textarea fields to still be a searchable field in some
    # databases
    $Self->{MaxLength} = 3800;

    return $Self;
}

sub ValueGet {
    my ( $Self, %Param ) = @_;

    my $DFValue = $Self->{DynamicFieldValueObject}->ValueGet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
    );

    return if !$DFValue;
    return if !IsArrayRefWithData($DFValue);
    return if !IsHashRefWithData( $DFValue->[0] );

    return $DFValue->[0]->{ValueText};
}

sub ValueSet {
    my ( $Self, %Param ) = @_;

    my $Success = $Self->{DynamicFieldValueObject}->ValueSet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        Value    => [
            {
                ValueText => $Param{Value},
            },
        ],
        UserID => $Param{UserID},
    );

    return $Success;
}

sub ValueDelete {
    my ( $Self, %Param ) = @_;

    my $Success = $Self->{DynamicFieldValueObject}->ValueDelete(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        UserID   => $Param{UserID},
    );

    return $Success;
}

sub AllValuesDelete {
    my ( $Self, %Param ) = @_;

    my $Success = $Self->{DynamicFieldValueObject}->AllValuesDelete(
        FieldID => $Param{DynamicFieldConfig}->{ID},
        UserID  => $Param{UserID},
    );

    return $Success;
}

sub ValueValidate {
    my ( $Self, %Param ) = @_;

    my $Success = $Self->{DynamicFieldValueObject}->ValueValidate(
        Value => {
            ValueText => $Param{Value},
        },
        UserID => $Param{UserID}
    );

    return $Success;
}

sub SearchSQLGet {
    my ( $Self, %Param ) = @_;

    my %Operators = (
        Equals            => '=',
        GreaterThan       => '>',
        GreaterThanEquals => '>=',
        SmallerThan       => '<',
        SmallerThanEquals => '<=',
    );

    if ( $Operators{ $Param{Operator} } ) {
        my $SQL = " $Param{TableAlias}.value_text $Operators{$Param{Operator}} '";
        $SQL .= $Self->{DBObject}->Quote( $Param{SearchTerm} ) . "' "; 
        return $SQL;
    }

    if ( $Param{Operator} eq 'Like' ) {

        my $SQL = $Self->{DBObject}->QueryCondition(
            Key   => "$Param{TableAlias}.value_text",
            Value => $Param{SearchTerm},
        );

        return $SQL;
    }

    $Self->{'LogObject'}->Log(
        'Priority' => 'error',
        'Message'  => "Unsupported Operator $Param{Operator}",
    );

    return;
}

sub SearchSQLOrderFieldGet {
    my ( $Self, %Param ) = @_;

    return "$Param{TableAlias}.value_text";
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $Value = '';

    # set the field value or default
    if ( $Param{UseDefaultValue} ) {
        $Value = ( defined $FieldConfig->{DefaultValue} ? $FieldConfig->{DefaultValue} : '' );
    }
    $Value = $Param{Value} if defined $Param{Value};

    # extract the dynamic field value form the web request
    my $FieldValue = $Self->EditFieldValueGet(
        %Param,
    );

    # set values from ParamObject if present
    if ( defined $FieldValue ) {
        $Value = $FieldValue;
    }

    # set the rows number
    my $RowsNumber
        = defined $FieldConfig->{Rows} && $FieldConfig->{Rows} ? $FieldConfig->{Rows} : '7';

    # set the cols number
    my $ColsNumber
        = defined $FieldConfig->{Cols} && $FieldConfig->{Cols} ? $FieldConfig->{Cols} : '42';

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldTextArea';
    if ( defined $Param{Class} && $Param{Class} ne '' ) {
        $FieldClass .= ' ' . $Param{Class};
    }

    # set field as mandatory
    $FieldClass .= ' Validate_Required' if $Param{Mandatory};

    # set error css class
    $FieldClass .= ' ServerError' if $Param{ServerError};

    # set validation class for maximum characters
    $FieldClass .= ' Validate_MaxLength';

    # create field HTML
    # the XHTML definition does not support maxlenght attribute for a textarea field, therefore
    # is nedded to be set by JS code (otherwise wc3 validator will complaint about it)
    # notice that some browsers count new lines \n\r as only 1 character in this cases the
    # validation framework might rise an error while the user is still capable to enter text in the
    # textarea, otherwise the maxlenght property will prevent to enter more text than the maximum
    my $HTMLString = <<"EOF";
<textarea class="$FieldClass" id="$FieldName" name="$FieldName" title="$FieldLabel" rows="$RowsNumber" cols="$ColsNumber" >$Value</textarea>
<!--dtl:js_on_document_complete-->
<script type="text/javascript">//<![CDATA[
  \$('#$FieldName').attr('maxlength','$Self->{MaxLength}');
//]]></script>
<!--dtl:js_on_document_complete-->
EOF

    # for client side validation
    my $DivID = $FieldName . 'Error';

    if ( $Param{Mandatory} ) {
        $HTMLString .= <<"EOF";
    <div id="$DivID" class="TooltipErrorMessage">
        <p>
            \$Text{"This field is required or The field content is too long! Maximum size is $Self->{MaxLength} characters."}
        </p>
    </div>
EOF
    }
    else {
        $HTMLString .= <<"EOF";
    <div id="$DivID" class="TooltipErrorMessage">
        <p>
            \$Text{"The field content is too long! Maximum size is $Self->{MaxLength} characters."}
        </p>
    </div>
EOF
    }

    if ($FieldConfig->{DisplayErrors}) {
    	my $DivID = $FieldName . 'Warning';
    	
    	# for client side validation
        $HTMLString .= <<"EOF";

    <div id="$DivID" class="TooltipErrorMessage">
        <p>
            \$Text{"[Debug mode]"}
        </p>
    </div>
EOF
    }

    if ( $Param{ServerError} ) {

        my $ErrorMessage = $Param{ErrorMessage} || 'This field is required.';
        my $DivID = $FieldName . 'ServerError';

        # for server side validation
        $HTMLString .= <<"EOF";
    <div id="$DivID" class="TooltipErrorMessage">
        <p>
            \$Text{"$ErrorMessage"}
        </p>
    </div>
EOF
    }

    # call EditLabelRender on the common backend
    my $LabelString = $Self->{BackendCommonObject}->EditLabelRender(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        Mandatory          => $Param{Mandatory} || '0',
        FieldName          => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    my $Value;

#    # check if there is a Template and retreive the dinalic field value from there
#    if ( IsHashRefWithData( $Param{Template} ) ) {
#        $Value = $Param{Template}->{$FieldName};
#    }
#
#    # otherwise get dynamic field value form param
#    else {
#        $Value = $Param{ParamObject}->GetParam( Param => $FieldName );
#    }

#    if ( defined $Param{ReturnTemplateStructure} && $Param{ReturnTemplateStructure} eq '1' ) {
#        return {
#            $FieldName => $Value,
#        };
#    }

    # USE FOR DEBUGGING PURPOSES
my $DEBUG = 0;
    #
 use Data::Dumper;
open ERRLOG, '>>/tmp/TA_'.$Param{DynamicFieldConfig}->{Name}.'.log' if $DEBUG;
#print ERRLOG Dumper($Param{ParamObject}->{Query}->{param}) if $DEBUG;

print ERRLOG $Param{ParamObject} if $DEBUG;
#close ERRLOG;

    my $query_needed = 0;

    my @SQLParameters_values;
    my @SQLParameters_values_refs;

    my @SQLParameters_keys = split(',', $Param{DynamicFieldConfig}->{Config}->{Parameters});

    my %SQLParameters_hash;
    for my $key (@SQLParameters_keys) {
        $SQLParameters_hash{$key} = undef;
    }

    if ( scalar(@SQLParameters_keys) && $Param{ParamObject} && defined $Param{ParamObject} && $Param{ParamObject}->GetParam( Param => 'TicketID') ) {
    	my %TicketInfo;
    	# get Ticket from cache:
    	if ($Param{LayoutObject}->{TicketObject}->{'Cache::GetTicket'.$Param{ParamObject}->GetParam( Param => 'TicketID')}{''}{1}) {
    		%TicketInfo = %{$Param{LayoutObject}->{TicketObject}->{'Cache::GetTicket'.$Param{ParamObject}->GetParam( Param => 'TicketID')}{''}{1}};
    	}
    	else {
                my $EncodeObject = Kernel::System::Encode->new(
                    ConfigObject => $Param{ParamObject}->{ConfigObject},
                );
                my $TimeObject = Kernel::System::Time->new(
                    ConfigObject => $Param{ParamObject}->{ConfigObject},
                    LogObject    => $Param{ParamObject}->{LogObject},
                );
                my $DBObject = Kernel::System::DB->new(
                    ConfigObject => $Param{ParamObject}->{ConfigObject},
                    EncodeObject => $EncodeObject,
                    LogObject    => $Param{ParamObject}->{LogObject},
                    MainObject   => $Param{ParamObject}->{MainObject},
                );
                my $TicketObject = Kernel::System::Ticket->new(
                    ConfigObject       => $Param{ParamObject}->{ConfigObject},
                    LogObject          => $Param{ParamObject}->{LogObject},
                    DBObject           => $DBObject,
                    MainObject         => $Param{ParamObject}->{MainObject},
                    TimeObject         => $TimeObject,
                    EncodeObject       => $EncodeObject,
                );
                %TicketInfo = $TicketObject->TicketGet(
                    TicketID      => $Param{ParamObject}->GetParam( Param => 'TicketID'),
                    DynamicFields => 1,         # Optional, default 0. To include the dynamic field values for this ticket on the return structure.
                    UserID        => 0,
                );
    	}

    	for my $key (@SQLParameters_keys) {
    		if ($key eq 'SelectedCustomerUser') {
    			$SQLParameters_hash{$key} = $TicketInfo{CustomerUserID};
    		}
    		else {
    			$SQLParameters_hash{$key} = $TicketInfo{$key};
    		}
    	}
    	print ERRLOG "[Got Ticket info:]\n" if $DEBUG;
    	print ERRLOG Dumper(\%TicketInfo) if $DEBUG;
    } 
 


    for my $key (@SQLParameters_keys) {
        # WP - BINI
        # Fix per estrarre i valori puliti dai parametri (es. 2||DATO)
        # 


	if ( $Param{ParamObject}->{Query}->{param}->{$key}[0] ) {
        	$Param{ParamObject}->{Query}->{param}->{$key}[0] =~ s/^([^|]+)\|\|(.+)$/$1/;
        	push(@SQLParameters_values, $Param{ParamObject}->{Query}->{param}->{$key}[0]);
        	push(@SQLParameters_values_refs, \$Param{ParamObject}->{Query}->{param}->{$key}[0]);
	} elsif ( $SQLParameters_hash{$key} ) {
		push(@SQLParameters_values,  $SQLParameters_hash{$key});
		push(@SQLParameters_values_refs, \$SQLParameters_hash{$key});
	}


        
        # WP - BINI - ex: push(@SQLParameters_values, $Param{ParamObject}->{Query}->{param}->{$key}[0]);
        
        # if the changed Element is in the parameter list, update data
        if ($Param{ParamObject}->{Query}->{param}->{ElementChanged} and $key eq $Param{ParamObject}->{Query}->{param}->{ElementChanged}[0]) {
                $query_needed = 1;
#                print ERRLOG $key." eq ".$Param{ParamObject}->{Query}->{param}->{ElementChanged}[0]."\n";
        }
        else {
#                print ERRLOG $key." neq ".$Param{ParamObject}->{Query}->{param}->{ElementChanged}[0]."\n";
        }
    }

    

#    print ERRLOG Dumper($Param{ParamObject});
#    print ERRLOG UNIVERSAL::isa($Param{ParamObject}, 'HASH')." FieldName: $FieldName\n";
#    close ERRLOG;

    print ERRLOG "Building value\n" if $DEBUG;

    if ($Param{ParamObject}->{Query}->{param}->{$FieldName} && $Param{ParamObject}->{Query}->{param}->{$FieldName}[0]) {
        $Value = $Param{ParamObject}->{Query}->{param}->{$FieldName}[0];
    }

#    if ($query_needed and 1) {


        $Value = $Self->{CacheObject}->Get(
            Type    => 'String',
            Key     => scalar @SQLParameters_values > 0 ? $Param{DynamicFieldConfig}->{Name} . join('', @SQLParameters_values) : $Param{DynamicFieldConfig}->{Name},
        );

        if (!$Value) {

	    print ERRLOG "Doing query\n" if $DEBUG;

	    my @row;
            my $sth;
            my $dbh;


	    my $completeline;

            # use local DB Object if no DBI string is specified.
            if ( !$Param{DynamicFieldConfig}->{Config}->{DBIstring} ) {
                $Self->{DBObject}->Prepare(
                    SQL => $Param{DynamicFieldConfig}->{Config}->{Query},
                    Bind => \@SQLParameters_values_refs,
                );
    
                #fetch first row
                @row = $Self->{DBObject}->FetchrowArray();
    
            } else {
                $dbh = DBI->connect($Param{DynamicFieldConfig}->{Config}->{DBIstring}, $Param{DynamicFieldConfig}->{Config}->{DBIuser}, $Param{DynamicFieldConfig}->{Config}->{DBIpass},
                                  { PrintError => 0, AutoCommit => 0 }) or die;
            
                $dbh->{'mysql_enable_utf8'} = 1;
        
                $sth = $dbh->prepare($Param{DynamicFieldConfig}->{Config}->{Query});
                $sth->execute( @SQLParameters_values );
        
                # fetch first row
                @row = $sth->fetchrow_array;        
            }
    
            print ERRLOG ":::Extracted from DB:::\n" if $DEBUG;
            print ERRLOG Dumper(@row) if $DEBUG;
            print ERRLOG "::::::::::::::::::::::::::\n" if $DEBUG;
            close ERRLOG if $DEBUG;
    
            # cicle fetched rows from DB
            my $line = '';
            while (@row) {

		my $counter = 0;
                my @names = $sth->{NAME};

                for my $col (@row) {
                    if (!utf8::is_utf8($col)) {
                        utf8::decode( $col );
                    }
#                    if (!$firstRow) { # skip first row 
#                        $firstRow = 1;
#                	next;
#                    }

		    if ( !$Param{DynamicFieldConfig}->{Config}->{DBIstring} ) {
                        $line .= $col."\n";
                    } else {
                    	$line .= $names[0][$counter].": ".$col."\n";
                    }
                    $counter += 1;
                }
    
#                if ($Param{DynamicFieldConfig}->{Config}->{StoreValue} && $Param{DynamicFieldConfig}->{Config}->{StoreValue} eq "1") {
#                    %PossibleValues = ( %PossibleValues, $row[0]."||".$line => $line);
#                }
#                else {
#                    %PossibleValues = ( %PossibleValues, $row[0] => $line );
#                }

#	 	$completeline .= $row[0] . ": ". $line;
   
                # fetch new row depending on DB connection type
                if ( !$Param{DynamicFieldConfig}->{Config}->{DBIstring} ) {
                    @row = $Self->{DBObject}->FetchrowArray();
                }
                else {
                    @row = $sth->fetchrow_array;
    		if (!@row) {
                        $dbh->disconnect;
                    }
                }
            }
    
	    $Value = $line;    
    





























#            my @row;
#	    my $sth;
#	    my $dbh;
#
#            my $line = '';
#
#	    if ( !$Param{DynamicFieldConfig}->{Config}->{DBIstring} ) {
#                $Self->{DBObject}->Prepare(
#                	SQL => $Param{DynamicFieldConfig}->{Config}->{Query},
#	                Bind => \@SQLParameters_values_refs,
#            	);
#
#                #fetch first row
#	        @row = $Self->{DBObject}->FetchrowArray();
#
#                while ( @row = $Self->{DBObject}->FetchrowArray()) {
#    
#                    my @names = $sth->{NAME};
#                    for my $col (@row) {
#                        $line .= $names[0][$counter].": ".$col."\n";
#                        $counter += 1;
#                    }
#                }
#
#            }
#            else {
#                $dbh = DBI->connect($Param{DynamicFieldConfig}->{Config}->{DBIstring}, $Param{DynamicFieldConfig}->{Config}->{DBIuser}, $Param{DynamicFieldConfig}->{Config}->{DBIpass},
#                    { RaiseError => 1, AutoCommit => 0 });
#                $sth = $dbh->prepare($Param{DynamicFieldConfig}->{Config}->{Query});
#                $sth->execute( @SQLParameters_values );
#    #    STAMPA LA QUERY
#    #    $Self->{'LogObject'}->Log(
#    #        'Priority' => 'notice',
#    #        'Message'  => "$Param{DynamicFieldConfig}->{Config}->{Query}",
#    #    );
#    #	    my $found = $sth->fetch();
#    #	    print ERRLOG "found $found rows\n" if $DEBUG;
#    
#                my $counter = 0;
#    
#
#    
#                while ( @row = $sth->fetchrow_array ) {
#    
#                    my @names = $sth->{NAME};
#                    for my $col (@row) {
#                        $line .= $names[0][$counter].": ".$col."\n";
#                        $counter += 1;
#                    }
#                }
#	    }
    
#            $Value = $line;
	
            $Self->{CacheObject}->Set(
                Type        => 'String',
            	Key	    => scalar @SQLParameters_values > 0 ? $Param{DynamicFieldConfig}->{Name} . join('', @SQLParameters_values) : $Param{DynamicFieldConfig}->{Name},
                Value       => $Value,
                TTL         => 360,
            );
        }
	else {
		print ERRLOG "Query not needed, using cache\n" if $DEBUG;
	}
#    }
    close ERRLOG if $DEBUG;

    return $Value;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Value = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this backend but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $ServerError;
    my $ErrorMessage;

    # perform necessary validations
    if ( $Param{Mandatory} && $Value eq '' ) {
        $ServerError = 1;
    }

    if ( length $Value > $Self->{MaxLength} ) {
        $ServerError = 1;
        $ErrorMessage
            = "The field content is too long! Maximum size is $Self->{MaxLength} characters.";
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => $ErrorMessage,
    };

    return $Result;
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    # set HTMLOuput as default if not specified
    if ( !defined $Param{HTMLOutput} ) {
        $Param{HTMLOutput} = 1;
    }

    # get raw Title and Value strings from field value
    my $Value = defined $Param{Value} ? $Param{Value} : '';
    my $Title = $Value;

    # HTMLOuput transformations
    if ( $Param{HTMLOutput} ) {

        $Value = $Param{LayoutObject}->Ascii2Html(
            Text           => $Value,
            HTMLResultMode => 1,
            Max            => $Param{ValueMaxChars} || '',
        );

        $Title = $Param{LayoutObject}->Ascii2Html(
            Text => $Title,
            Max => $Param{TitleMaxChars} || '',
        );
    }
    else {
        if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
            $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
        }
        if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
            $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
        }
    }

    # this field type does not support the Link Feature
    my $Link;

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
        Link  => $Link,
    };

    return $Data;
}

sub IsSortable {
    my ( $Self, %Param ) = @_;

    return 0;
}

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    # set the field value
    my $Value = ( defined $Param{DefaultValue} ? $Param{DefaultValue} : '' );

    # get the field value, this fuction is always called after the profile is loaded
    my $FieldValue = $Self->SearchFieldValueGet(%Param);

    # set values from profile if present
    if ( defined $FieldValue ) {
        $Value = $FieldValue;
    }

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldText';

    my $HTMLString = <<"EOF";
<input type="text" class="$FieldClass" id="$FieldName" name="$FieldName" title="$FieldLabel" value="$Value" />
EOF

    # call EditLabelRender on the common backend
    my $LabelString = $Self->{BackendCommonObject}->EditLabelRender(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        FieldName          => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $Value;

    # get dynamic field value form param object
    if ( defined $Param{ParamObject} ) {
        $Value = $Param{ParamObject}
            ->GetParam( Param => 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} );
    }

    # otherwise get the value from the profile
    elsif ( defined $Param{Profile} ) {
        $Value = $Param{Profile}->{ 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} };
    }
    else {
        return;
    }

    if ( defined $Param{ReturnProfileStructure} && $Param{ReturnProfileStructure} eq 1 ) {
        return {
            'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name} => $Value,
        };
    }

    return $Value;

}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # get field value
    my $Value = $Self->SearchFieldValueGet(%Param);

    if ( !$Value ) {
        return {
            Parameter => {
                'Like' => '',
            },
            Display => '',
            }
    }

    # return search parameter structure
    return {
        Parameter => {
            'Like' => '*' . $Value . '*',
        },
        Display => $Value,
    };
}

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    return {
        Name    => $Param{DynamicFieldConfig}->{Label},
        Element => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
    };
}

sub CommonSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Operator = 'Equals';
    my $Value    = $Param{Value};

    return {
        $Operator => $Value,
    };
}

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';
    my $Title = $Value;

    # cut strings if needed
    if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }
    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
    };

    return $Data;
}

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # set the field types
    my $EditValueType   = 'SCALAR';
    my $SearchValueType = 'SCALAR';

    # return the correct structure
    if ( $Param{FieldType} eq 'Edit' ) {
        return {
            $FieldName => $EditValueType,
            }
    }
    elsif ( $Param{FieldType} eq 'Search' ) {
        return {
            'Search_' . $FieldName => $SearchValueType,
            }
    }
    else {
        return {
            $FieldName             => $EditValueType,
            'Search_' . $FieldName => $SearchValueType,
            }
    }
}

sub IsAJAXUpdateable {
    my ( $Self, %Param ) = @_;

    return 0;
}

sub RandomValueSet {
    my ( $Self, %Param ) = @_;

    my $Value = int( rand(500) );

    my $Success = $Self->ValueSet(
        %Param,
        Value => $Value,
    );

    if ( !$Success ) {
        return {
            Success => 0,
        };
    }
    return {
        Success => 1,
        Value   => $Value,
    };
}

sub IsMatchable {
    my ( $Self, %Param ) = @_;

    return 1;
}

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    # return false if not match
    if ( $Param{ObjectAttributes}->{$FieldName} ne $Param{Value} ) {
        return 0;
    }

    return 1;
}

sub AJAXPossibleValuesGet {
    my ( $Self, %Param ) = @_;

    # not supported
    return;
}

sub HistoricalValuesGet {
    my ( $Self, %Param ) = @_;

    # get historical values from database
    my $HistoricalValues = $Self->{DynamicFieldValueObject}->HistoricalValueGet(
        FieldID   => $Param{DynamicFieldConfig}->{ID},
        ValueType => 'Text',
    );

    # retrun the historical values from database
    return $HistoricalValues;
}


sub ValueLookup {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Key} ? $Param{Key} : '';

    # get real values
    my $PossibleValues = $Param{DynamicFieldConfig}->{Config}->{PossibleValues};

    if ($Value) {

        # check if there is a real value for this key (otherwise keep the key)
        if ( $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Value} ) {

            # get readeable value
            $Value = $Param{DynamicFieldConfig}->{Config}->{PossibleValues}->{$Value};

            # check if translation is possible
            if (
                defined $Param{LanguageObject}
                && $Param{DynamicFieldConfig}->{Config}->{TranslatableValues}
                )
            {

                # translate value
                $Value = $Param{LanguageObject}->Get($Value);
            }
        }
    }

    return $Value;
}


1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$$

=cut
