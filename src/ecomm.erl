%%#!/usr/bin/env escript
%%
%% ecomm.erl ported from LibSnert's comm.java
%%

-module(ecomm).
-export([main/1, comm/3]).

-define(BUFSIZ, 1024).
-define(FLAG_COLUMN_1, 1).
-define(FLAG_COLUMN_2, 2).
-define(FLAG_COLUMN_3, 4).
-define(FLAG_COLUMN_MASK, 7).
-define(INDENTS, {"", "\t", "\t", "\t\t"}).

usage() ->
	io:format("usage: ecomm [-123f] file1 file2~n"),
	io:format("-1\t\tsuppress output column of lines unique to file1~n"),
	io:format("-2\t\tsuppress output column of lines unique to file2~n"),
	io:format("-3\t\tsuppress output column of lines duplicated in file1 and file2.~n"),
	io:format("-f\t\tfold case in line comparisons~n"),
	halt(2).

main(Args) ->
	case egetopt:parse(Args, [
		{ $1, flag, no_col_1 },
		{ $2, flag, no_col_2 },
		{ $3, flag, no_col_3 },
		{ $f, flag, fold_case }
	]) of
	{ok, Options, ArgsN} ->
		process(Options, ArgsN);
	{error, Reason, Opt} ->
		io:format("~s -~c~n", [Reason, Opt]),
		usage()
	end.

process(_Opts, Files) when length(Files) /= 2 ->
	usage();
process(Opts, [File1, File2]) ->
	try
		process(Opts, File1, File2)
	catch
		throw:{error, File, Reason} ->
			io:format(standard_error, "ecomm: ~s: ~s~n", [File, str:error(Reason)]),
			halt(1)
	end.

process(Opts, File1, File2) ->
	Fp1 = case file:open(File1, [read, binary, {read_ahead, ?BUFSIZ}]) of
	{error, Reason1} ->
		throw({error, File1, Reason1});
	{ok, Fp_1} ->
		Fp_1
	end,

	Fp2 = case file:open(File2, [read, binary, {read_ahead, ?BUFSIZ}]) of
	{error, Reason2} ->
		throw({error, File2, Reason2});
	{ok, Fp_2} ->
		Fp_2
	end,

	comm(Fp1, Fp2, Opts),

	file:close(Fp1),
	file:close(Fp2).

comm(Fp1, Fp2, Opts) ->
	Col1 = ?FLAG_COLUMN_MASK band case proplists:get_value(no_col_1, Opts, false) of
	true -> bnot ?FLAG_COLUMN_1;
	false -> ?FLAG_COLUMN_MASK
	end,

	Col2 = Col1 band case proplists:get_value(no_col_2, Opts, false) of
	true -> bnot ?FLAG_COLUMN_2;
	false -> ?FLAG_COLUMN_MASK
	end,

	Flags = Col2 band case proplists:get_value(no_col_3, Opts, false) of
	true -> bnot ?FLAG_COLUMN_3;
	false -> ?FLAG_COLUMN_MASK
	end,

	Cmp = case proplists:get_value(fold_case, Opts, false) of
	true ->
		fun str:casecmp/2;
	false ->
		fun str:cmp/2
	end,

	comm(Fp1, Fp2, <<>>, <<>>, Cmp, Flags, 0).

comm(Fp1, Fp2, CurrLine1, CurrLine2, Cmp, Flags, Diff) ->
	Line1 = if
	Diff =< 0 ->
		case file:read_line(Fp1) of
		eof ->
			eof;
		{ok, Line_1} ->
			str:rtrim(Line_1);
		Error1 ->
			throw(Error1)
		end;
	Diff > 0 ->
		CurrLine1
	end,

	Line2 = if
	Diff >= 0 ->
		case file:read_line(Fp2) of
		eof ->
			eof;
		{ok, Line_2} ->
			str:rtrim(Line_2);
		Error2 ->
			throw(Error2)
		end;
	Diff < 0 ->
		CurrLine2
	end,

	case {Line1, Line2} of
	{eof, eof} ->
		ok;
	{eof, _} ->
		output_column(Line1, Line2, Flags, 1),
		comm(Fp1, Fp2, Line1, Line2, Cmp, Flags, 1);
	{_, eof} ->
		output_column(Line1, Line2, Flags, -1),
		comm(Fp1, Fp2, Line1, Line2, Cmp, Flags, -1);
	_ ->
		NextDiff = Cmp(Line1, Line2),
		output_column(Line1, Line2, Flags, NextDiff),
		comm(Fp1, Fp2, Line1, Line2, Cmp, Flags, NextDiff)
	end.

output_column(Line1, _, Flags, 0) ->
	if
	(Flags band ?FLAG_COLUMN_3) /= 0 ->
		io:format("~s~s~n", [element(1+(Flags band bnot ?FLAG_COLUMN_3), ?INDENTS), Line1]);
	true ->
		ok
	end;
output_column(_, Line2, Flags, 1) ->
	if
	(Flags band ?FLAG_COLUMN_2) /= 0 ->
		io:format("~s~s~n", [element(1+(Flags band ?FLAG_COLUMN_1), ?INDENTS), Line2]);
	true ->
		ok
	end;
output_column(Line1, _, Flags, _) ->
	if
	(Flags band ?FLAG_COLUMN_1) /= 0 ->
		io:format("~s~n", [Line1]);
	true ->
		ok
	end.
