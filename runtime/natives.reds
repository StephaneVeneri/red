Red/System [
	Title:   "Red native functions"
	Author:  "Nenad Rakocevic"
	File: 	 %natives.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2011-2015 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#define RETURN_NONE [
	stack/reset
	none/push-last
	exit
]

natives: context [
	verbose:  0
	lf?: 	  no										;-- used to print or not an ending newline
	last-lf?: no
	
	table: declare int-ptr!
	top: 1
	
	buffer-blk: as red-block! 0

	register: func [
		[variadic]
		count	   [integer!]
		list	   [int-ptr!]
		/local
			offset [integer!]
	][
		offset: 0
		
		until [
			table/top: list/value
			top: top + 1
			assert top <= NATIVES_NB
			list: list + 1
			count: count - 1
			zero? count
		]
	]
	
	;--- Natives ----
	
	if*: func [check? [logic!]][
		#typecheck if
		either logic/false? [
			RETURN_NONE
		][
			interpreter/eval as red-block! stack/arguments + 1 yes
		]
	]
	
	unless*: func [check? [logic!]][
		#typecheck -unless-								;-- `unless` would be converted to `if not` by lexer
		either logic/false? [
			interpreter/eval as red-block! stack/arguments + 1 yes
		][
			RETURN_NONE
		]
	]
	
	either*: func [
		check? [logic!]
		/local offset [integer!]
	][
		#typecheck either
		offset: either logic/true? [1][2]
		interpreter/eval as red-block! stack/arguments + offset yes
	]
	
	any*: func [
		check? [logic!]
		/local
			value [red-value!]
			tail  [red-value!]
	][
		#typecheck any
		value: block/rs-head as red-block! stack/arguments
		tail:  block/rs-tail as red-block! stack/arguments
		
		while [value < tail][
			value: interpreter/eval-next value tail no
			if logic/true? [exit]
		]
		RETURN_NONE
	]
	
	all*: func [
		check? [logic!]
		/local
			value [red-value!]
			tail  [red-value!]
	][
		#typecheck all
		value: block/rs-head as red-block! stack/arguments
		tail:  block/rs-tail as red-block! stack/arguments
		
		if value = tail [RETURN_NONE]
		
		while [value < tail][
			value: interpreter/eval-next value tail no
			if logic/false? [RETURN_NONE]
		]
	]
	
	while*:	func [
		check? [logic!]
		/local
			cond  [red-block!]
			body  [red-block!]
	][
		#typecheck while
		cond: as red-block! stack/arguments
		body: as red-block! stack/arguments + 1
		
		stack/mark-loop words/_body
		while [
			interpreter/eval cond yes
			logic/true?
		][
			stack/reset
			catch RED_THROWN_BREAK [interpreter/eval body yes]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[0]
				default				[re-throw]
			]
		]
		stack/unwind
		stack/reset
		unset/push-last
	]
	
	until*: func [
		check? [logic!]
		/local
			body  [red-block!]
	][
		#typecheck until
		body: as red-block! stack/arguments

		stack/mark-loop words/_body
		until [
			stack/reset
			catch RED_THROWN_BREAK	[interpreter/eval body yes]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[0]
				default				[re-throw]
			]
			logic/true?
		]
		stack/unwind-last
	]
	
	loop*: func [
		[catch]
		check? [logic!]
		/local
			body  [red-block!]
			count [integer!]
			id 	  [integer!]
			saved [int-ptr!]
	][
		#typecheck loop
		count: integer/get*
		unless positive? count [RETURN_NONE]			;-- if counter <= 0, no loops
		body: as red-block! stack/arguments + 1
		
		stack/mark-loop words/_body		
		loop count [
			stack/reset
			saved: system/stack/top						;--	FIXME: solve loop/catch conflict
			interpreter/eval body yes
			system/stack/top: saved
			
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[0]
				default				[id: system/thrown throw id]
			]
		]
		stack/unwind-last
	]
	
	repeat*: func [
		check? [logic!]
		/local
			w	   [red-word!]
			body   [red-block!]
			count  [red-integer!]
			cnt	   [integer!]
			i	   [integer!]
	][
		#typecheck repeat
		
		w: 	   as red-word!    stack/arguments
		count: as red-integer! stack/arguments + 1
		body:  as red-block!   stack/arguments + 2
		
		i: integer/get as red-value! count
		unless positive? i [RETURN_NONE]				;-- if counter <= 0, no loops
		
		count/value: 1
	
		stack/mark-loop words/_body
		until [
			stack/reset
			_context/set w as red-value! count
			catch RED_THROWN_BREAK [interpreter/eval body yes]
			switch system/thrown [
				RED_THROWN_BREAK [system/thrown: 0 break]
				RED_THROWN_CONTINUE
				0 [
					system/thrown: 0
					count/value: count/value + 1
					i: i - 1
				]
				default	[re-throw]
			]
			zero? i
		]
		stack/unwind-last
	]
	
	forever*: func [
		check? [logic!]
		/local
			body  [red-block!]
	][
		#typecheck -forever-							;-- `forever` would be replaced by lexer
		body: as red-block! stack/arguments
		
		stack/mark-loop words/_body
		forever [
			catch RED_THROWN_BREAK	[interpreter/eval body no]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 					[stack/pop 1]
				default				[re-throw]
			]
		]
		stack/unwind-last
	]
	
	foreach*: func [
		check? [logic!]
		/local
			value [red-value!]
			body  [red-block!]
			size  [integer!]
	][
		#typecheck foreach
		value: stack/arguments
		body: as red-block! stack/arguments + 2
		
		stack/push stack/arguments + 1					;-- copy arguments to stack top in reverse order
		stack/push value								;-- (required by foreach-next)
		
		stack/mark-loop words/_body
		stack/set-last unset-value
		
		either TYPE_OF(value) = TYPE_BLOCK [
			size: block/rs-length? as red-block! value
			
			while [foreach-next-block size][			;-- foreach [..]
				stack/reset
				catch RED_THROWN_BREAK	[interpreter/eval body no]
				switch system/thrown [
					RED_THROWN_BREAK	[system/thrown: 0 break]
					RED_THROWN_CONTINUE	[system/thrown: 0 continue]
					0 					[0]
					default				[re-throw]
				]
			]
		][
			while [foreach-next][						;-- foreach <word!>
				stack/reset
				catch RED_THROWN_BREAK	[interpreter/eval body no]
				switch system/thrown [
					RED_THROWN_BREAK	[system/thrown: 0 break]
					RED_THROWN_CONTINUE	[system/thrown: 0 continue]
					0 					[0]
					default				[re-throw]
				]
			]
		]
		stack/unwind-last
	]
	
	forall*: func [
		check? [logic!]
		/local
			w 	   [red-word!]
			body   [red-block!]
			saved  [red-value!]
			series [red-series!]
	][
		#typecheck forall
		w:    as red-word!  stack/arguments
		body: as red-block! stack/arguments + 1
		
		saved: word/get w							;-- save series (for resetting on end)
		w: word/push w								;-- word argument
		
		stack/mark-loop words/_body
		while [loop? as red-series! _context/get w][
			stack/reset
			catch RED_THROWN_BREAK	[interpreter/eval body no]
			switch system/thrown [
				RED_THROWN_BREAK	[system/thrown: 0 break]
				RED_THROWN_CONTINUE	[system/thrown: 0 continue]
				0 [
					series: as red-series! _context/get w
					series/head: series/head + 1
				]
				default	[re-throw]
			]
		]
		stack/unwind-last
		_context/set w saved
	]
	
	func*: func [check? [logic!]][
		#typecheck func
		_function/validate as red-block! stack/arguments
		_function/push 
			as red-block! stack/arguments
			as red-block! stack/arguments + 1
			null
			0
			null
		stack/set-last stack/top - 1
	]
	
	function*: func [check? [logic!]][
		#typecheck function
		_function/collect-words
			as red-block! stack/arguments
			as red-block! stack/arguments + 1
		func* check?
	]
	
	does*: func [check? [logic!]][
		#typecheck -does-								;-- `does` would be replaced by lexer
		copy-cell stack/arguments stack/push*
		block/make-at as red-block! stack/arguments 1
		func* check?
	]
	
	has*: func [
		check? [logic!]
		/local blk [red-block!]
	][
		#typecheck has
		blk: as red-block! stack/arguments
		block/insert-value blk as red-value! refinements/local
		blk/head: blk/head - 1
		func* check?
	]
		
	switch*: func [
		check?   [logic!]
		default? [integer!]
		/local
			pos	 [red-value!]
			blk  [red-block!]
			alt  [red-block!]
			end  [red-value!]
			s	 [series!]
	][
		#typecheck [switch default?]
		blk: as red-block! stack/arguments + 1
		alt: as red-block! stack/arguments + 2
		
		pos: actions/find
			as red-series! blk
			stack/arguments
			null
			yes											;-- /only
			no
			no
			null
			null
			no
			no
			yes											;-- /tail
			no
			
		either TYPE_OF(pos) = TYPE_NONE [
			either negative? default? [
				RETURN_NONE
			][
				interpreter/eval alt yes
				exit									;-- early exit with last value on stack
			]
		][
			s: GET_BUFFER(blk)
			end: s/tail
			pos: _series/pick as red-series! pos 1 null
			
			while [pos < end][							;-- find first following block
				if TYPE_OF(pos) = TYPE_BLOCK [
					stack/reset
					interpreter/eval as red-block! pos yes	;-- do the block
					exit								;-- early exit with last value on stack
				]
				pos: pos + 1
			]
		]
		RETURN_NONE
	]
	
	case*: func [
		check?	  [logic!]
		all? 	  [integer!]
		/local
			value [red-value!]
			tail  [red-value!]
	][
		#typecheck [case all?]
		value: block/rs-head as red-block! stack/arguments
		tail:  block/rs-tail as red-block! stack/arguments
		if value = tail [RETURN_NONE]
		
		while [value < tail][
			value: interpreter/eval-next value tail no	;-- eval condition
			if value = tail [break]
			either logic/true? [
				either TYPE_OF(value) = TYPE_BLOCK [	;-- if true, eval what follows it
					stack/reset
					interpreter/eval as red-block! value yes
					value: value + 1
				][
					value: interpreter/eval-next value tail no
				]
				if negative? all? [exit]				;-- early exit with last value on stack (unless /all)
			][
				value: value + 1						;-- single value only allowed for cases bodies
			]
		]
		RETURN_NONE
	]
	
	do*: func [
		check?  [logic!]
		args 	[integer!]
		return: [integer!]
		/local
			cframe [byte-ptr!]
			arg	   [red-value!]
			do-arg [red-value!]
			str	   [red-string!]
			out    [red-string!]
			len	   [integer!]
	][
		#typecheck [do args]
		arg: stack/arguments
		cframe: stack/get-ctop							;-- save the current call frame pointer
		do-arg: stack/arguments + args
		
		if OPTION?(do-arg) [
			copy-cell do-arg #get system/script/args
		]
		
		catch RED_THROWN_BREAK [
			switch TYPE_OF(arg) [
				TYPE_BLOCK [
					interpreter/eval as red-block! arg yes
				]
				TYPE_PATH [
					interpreter/eval-path arg arg arg + 1 no no no no
					stack/set-last arg + 1
				]
				TYPE_STRING [
					str: as red-string! arg
					#call [system/lexer/transcode str none]
					interpreter/eval as red-block! arg yes
				]
				TYPE_FILE [
					str: as red-string! simple-io/read as red-file! arg no no
					#call [system/lexer/transcode str none]
					interpreter/eval as red-block! arg yes
				]
				TYPE_ERROR [
					stack/throw-error as red-object! arg
				]
				default [
					interpreter/eval-expression arg arg + 1 no no
				]
			]
		]
		switch system/thrown [
			RED_THROWN_BREAK
			RED_THROWN_CONTINUE
			RED_THROWN_RETURN
			RED_THROWN_EXIT [
				either stack/eval? cframe [				;-- if run from interpreter,
					re-throw 							;-- let the exception pass through
					0									;-- 0 to make compiler happy		
				][
					system/thrown						;-- request an early exit from caller
				]
			]
			0			[0]
			default 	[re-throw 0]					;-- 0 to make compiler happy
		]
	]
	
	get*: func [
		check? [logic!]
		any?   [integer!]
		case?  [integer!]
		/local
			value [red-value!]
	][
		#typecheck [get any? case?]
		value: stack/arguments
		
		switch TYPE_OF(value) [
			TYPE_PATH
			TYPE_GET_PATH
			TYPE_SET_PATH
			TYPE_LIT_PATH [
				interpreter/eval-path value null null no yes no case? <> -1
			]
			TYPE_OBJECT [
				object/reflect as red-object! value words/values
			]
			default [
				stack/set-last _context/get as red-word! stack/arguments
			]
		]
	]
	
	set*: func [
		check? [logic!]
		any?   [integer!]
		case?  [integer!]
		_only? [integer!]
		_some? [integer!]
		/local
			w	  [red-word!]
			value [red-value!]
			blk	  [red-block!]
			only? [logic!]
			some? [logic!]
	][
		#typecheck [set any? case? _only? _some?]
		w: as red-word! stack/arguments
		value: stack/arguments + 1
		only?: _only? <> -1
		some?: _some? <> -1
		
		switch TYPE_OF(w) [
			TYPE_PATH
			TYPE_GET_PATH
			TYPE_SET_PATH
			TYPE_LIT_PATH [
				value: stack/push stack/arguments
				copy-cell stack/arguments + 1 stack/arguments
				interpreter/eval-path value null null yes no no case? <> -1
			]
			TYPE_OBJECT [
				object/set-many as red-object! w value only? some?
				stack/set-last value
			]
			TYPE_MAP [
				map/set-many as red-hash! w as red-block! value only? some?
				stack/set-last value
			]
			TYPE_BLOCK [
				blk: as red-block! w
				set-many blk value block/rs-length? blk only? some?
				stack/set-last value
			]
			default [
				stack/set-last _context/set w value
			]
		]
	]

	print*: func [check? [logic!]][
		lf?: yes											;@@ get rid of this global state
		prin* check?
		lf?: no
		last-lf?: yes
	]
	
	prin*: func [
		check? [logic!]
		/local
			arg		[red-value!]
			str		[red-string!]
			blk		[red-block!]
			series	[series!]
			offset	[byte-ptr!]
			size	[integer!]
			unit	[integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/prin"]]
		#typecheck -prin-									;-- `prin` would be replaced by lexer
		arg: stack/arguments

		if TYPE_OF(arg) = TYPE_BLOCK [
			block/rs-clear buffer-blk
			stack/push as red-value! buffer-blk
			assert stack/top - 2 = stack/arguments			;-- check for correct stack layout
			reduce* no 1
			blk: as red-block! arg
			blk/head: 0										;-- head changed by reduce/into
		]

		actions/form* -1
		str: as red-string! stack/arguments
		assert any [
			TYPE_OF(str) = TYPE_STRING
			TYPE_OF(str) = TYPE_SYMBOL						;-- symbol! and string! structs are overlapping
		]
		series: GET_BUFFER(str)
		unit: GET_UNIT(series)
		offset: (as byte-ptr! series/offset) + (str/head << (log-b unit))
		size: as-integer (as byte-ptr! series/tail) - offset

		either lf? [
			switch unit [
				Latin1 [platform/print-line-Latin1 as c-string! offset size]
				UCS-2  [platform/print-line-UCS2 				offset size]
				UCS-4  [platform/print-line-UCS4   as int-ptr!  offset size]

				default [									;@@ replace by an assertion
					print-line ["Error: unknown string encoding: " unit]
				]
			]
		][
			switch unit [
				Latin1 [platform/print-Latin1 as c-string! offset size]
				UCS-2  [platform/print-UCS2   			   offset size]
				UCS-4  [platform/print-UCS4   as int-ptr!  offset size]

				default [									;@@ replace by an assertion
					print-line ["Error: unknown string encoding: " unit]
				]
			]
		]
		last-lf?: no
		stack/set-last unset-value
	]
	
	equal?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/equal?"]]
		actions/compare* COMP_EQUAL
	]
	
	not-equal?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/not-equal?"]]
		actions/compare* COMP_NOT_EQUAL
	]
	
	strict-equal?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/strict-equal?"]]
		actions/compare* COMP_STRICT_EQUAL
	]
	
	lesser?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/lesser?"]]
		actions/compare* COMP_LESSER
	]
	
	greater?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/greater?"]]
		actions/compare* COMP_GREATER
	]
	
	lesser-or-equal?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/lesser-or-equal?"]]
		actions/compare* COMP_LESSER_EQUAL
	]	
	
	greater-or-equal?*: func [
		check?  [logic!]
		return: [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/greater-or-equal?"]]
		actions/compare* COMP_GREATER_EQUAL
	]
	
	same?: func [
		arg1    [red-value!]
		arg2    [red-value!]
		return:	[logic!]
		/local
			result [red-logic!]
			type   [integer!]
			res    [logic!]
	][
		type: TYPE_OF(arg1)
		res: false
		
		if type = TYPE_OF(arg2) [
			case [
				any [
					type = TYPE_DATATYPE
					type = TYPE_LOGIC
					type = TYPE_OBJECT
				][
					res: arg1/data1 = arg2/data1
				]
				any [
					type = TYPE_CHAR
					type = TYPE_INTEGER
					type = TYPE_BITSET
				][
					res: arg1/data2 = arg2/data2
				]
				ANY_SERIES?(type) [
					res: all [arg1/data1 = arg2/data1 arg1/data2 = arg2/data2]
				]
				type = TYPE_FLOAT	[
					res: all [arg1/data2 = arg2/data2 arg1/data3 = arg2/data3]
				]
				type = TYPE_NONE	[res: type = TYPE_OF(arg2)]
				true [
					res: all [
						arg1/data1 = arg2/data1
						arg1/data2 = arg2/data2
						arg1/data3 = arg2/data3
					]
				]
			]
		]
		res
	]
	
	same?*: func [
		check?  [logic!]
		return:	[red-logic!]
		/local
			result [red-logic!]
			arg1   [red-value!]
			arg2   [red-value!]
	][
		arg1: stack/arguments
		arg2: arg1 + 1
		
		result: as red-logic! arg1
		result/value: same? arg1 arg2
		result/header: TYPE_LOGIC
		result
	]

	not*: func [
		check? [logic!]
		/local
			bool [red-logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "native/not"]]
		
		bool: as red-logic! stack/arguments
		bool/value: logic/false?						;-- run test before modifying stack
		bool/header: TYPE_LOGIC
	]
	
	type?*: func [
		check?   [logic!]
		word?	 [integer!]
		return:  [red-value!]
		/local
			dt	 [red-datatype!]
			w	 [red-word!]
			name [names!]
	][
		#typecheck [type? word?]
		
		either negative? word? [
			dt: as red-datatype! stack/arguments		;-- overwrite argument
			dt/value: TYPE_OF(dt)						;-- extract type before overriding
			dt/header: TYPE_DATATYPE
			as red-value! dt
		][
			w: as red-word! stack/arguments				;-- overwrite argument
			name: name-table + TYPE_OF(w)				;-- point to the right datatype name record
			stack/set-last as red-value! name/word
		]
	]
	
	reduce*: func [
		check? [logic!]
		into   [integer!]
		/local
			value [red-value!]
			tail  [red-value!]
			arg	  [red-value!]
			into? [logic!]
			blk?  [logic!]
	][
		#typecheck [reduce into]
		arg: stack/arguments
		blk?: TYPE_OF(arg) = TYPE_BLOCK
		into?: into >= 0

		if blk? [
			value: block/rs-head as red-block! arg
			tail:  block/rs-tail as red-block! arg
		]

		stack/mark-native words/_body

		either into? [
			as red-block! stack/push arg + into
		][
			if blk? [block/push-only* (as-integer tail - value) >> 4]
		]

		either blk? [
			while [value < tail][
				value: interpreter/eval-next value tail yes
				either into? [actions/insert* -1 0 -1][block/append*]
				stack/keep									;-- preserve the reduced block on stack
			]
		][
			interpreter/eval-expression arg arg + 1 no yes	;-- for non block! values
			if into? [actions/insert* -1 0 -1]
		]
		stack/unwind-last
	]
	
	compose-block: func [
		blk		[red-block!]
		deep?	[logic!]
		only?	[logic!]
		into	[red-block!]
		root?	[logic!]
		return: [red-block!]
		/local
			value  [red-value!]
			tail   [red-value!]
			new	   [red-block!]
			result [red-value!]
			into?  [logic!]
	][
		value: block/rs-head blk
		tail:  block/rs-tail blk
		into?: all [root? OPTION?(into)]

		new: either into? [
			into
		][
			block/push-only* (as-integer tail - value) >> 4	
		]
		while [value < tail][
			switch TYPE_OF(value) [
				TYPE_BLOCK [
					blk: either deep? [
						compose-block as red-block! value deep? only? into no
					][
						as red-block! value
					]
					either into? [
						block/insert-value new as red-value! blk
					][
						copy-cell as red-value! blk ALLOC_TAIL(new)
					]
				]
				TYPE_PAREN [
					blk: as red-block! value
					unless zero? block/rs-length? blk [
						interpreter/eval blk yes
						result: stack/arguments
						blk: as red-block! result 
						
						unless any [
							TYPE_OF(result) = TYPE_UNSET
							all [
								not only?
								TYPE_OF(result) = TYPE_BLOCK
								zero? block/rs-length? blk
							]
						][
							either any [
								only? 
								TYPE_OF(result) <> TYPE_BLOCK
							][
								either into? [
									block/insert-value new result
								][
									copy-cell result ALLOC_TAIL(new)
								]
							][
								either into? [
									block/insert-block new as red-block! result
								][
									block/rs-append-block new as red-block! result
								]
							]
						]
					]
				]
				default [
					either into? [
						block/insert-value new value
					][
						copy-cell value ALLOC_TAIL(new)
					]
				]
			]
			value: value + 1
		]
		new
	]
	
	compose*: func [
		check?  [logic!]
		deep	[integer!]
		only	[integer!]
		into	[integer!]
		/local
			arg	  [red-value!]
			into? [logic!]
	][
		#typecheck [compose deep only into]
		arg: stack/arguments
		either TYPE_OF(arg) <> TYPE_BLOCK [					;-- pass-thru for non block! values
			into?: into >= 0
			stack/mark-native words/_body
			if into? [as red-block! stack/push arg + into]
			interpreter/eval-expression arg arg + 1 no yes
			if into? [actions/insert* -1 0 -1]
			stack/unwind-last
		][
			stack/set-last
				as red-value! compose-block
					as red-block! arg
					as logic! deep + 1
					as logic! only + 1
					as red-block! stack/arguments + into
					yes
		]
	]
	
	stats*: func [
		check?  [logic!]
		show	[integer!]
		info	[integer!]
		/local
			blk [red-block!]
	][
		#typecheck [stats show info]
		case [
			show >= 0 [
				;TBD
				integer/box memory/total
			]
			info >= 0 [
				blk: block/push* 5
				memory-info blk 2
				stack/set-last as red-value! blk
			]
			true [
				integer/box memory/total
			]
		]
	]
	
	bind*: func [
		check? [logic!]
		copy [integer!]
		/local
			value [red-value!]
			ref	  [red-value!]
			fun	  [red-function!]
			word  [red-word!]
			ctx	  [node!]
	][
		#typecheck [bind copy]
		value: stack/arguments
		ref: value + 1
		
		either any [
			TYPE_OF(ref) = TYPE_FUNCTION
			;TYPE_OF(ref) = TYPE_OBJECT
		][
			fun: as red-function! ref
			ctx: fun/ctx
		][
			word: as red-word! ref
			ctx: word/ctx
		]
		
		either TYPE_OF(value) = TYPE_BLOCK [
			either negative? copy [
				_context/bind as red-block! value TO_CTX(ctx) null no
			][
				stack/set-last 
					as red-value! _context/bind
						block/clone as red-block! value yes no
						TO_CTX(ctx)
						null
						no
			]
		][
			word: as red-word! value
			word/ctx: ctx
			word/index: _context/find-word TO_CTX(ctx) word/symbol no
		]
	]
	
	in*: func [
		check? [logic!]
		/local
			obj  [red-object!]
			ctx  [red-context!]
			word [red-word!]
			res	 [red-value!]
	][
		#typecheck in
		obj:  as red-object! stack/arguments
		word: as red-word! stack/arguments + 1
		ctx: GET_CTX(obj)
		
		switch TYPE_OF(word) [
			TYPE_WORD
			TYPE_GET_WORD
			TYPE_SET_WORD
			TYPE_LIT_WORD
			TYPE_REFINEMENT [
				either negative? _context/bind-word ctx word [
					res: as red-value! none-value
				][
					res: as red-value! word
				]
				stack/set-last res
			]
			TYPE_BLOCK
			TYPE_PAREN [
				0
			]
			default [0]
		]
	]

	parse*: func [
		check?  [logic!]
		case?	[integer!]
		;strict? [integer!]
		part	[integer!]
		trace	[integer!]
		return: [integer!]
		/local
			op	   [integer!]
			input  [red-series!]
			limit  [red-series!]
			int	   [red-integer!]
			res	   [red-value!]
			cframe [byte-ptr!]
	][
		#typecheck [parse case? part trace]
		op: either as logic! case? + 1 [COMP_STRICT_EQUAL][COMP_EQUAL]
		
		input: as red-series! stack/arguments
		limit: as red-series! stack/arguments + part
		part: 0
		
		if OPTION?(limit) [
			part: either TYPE_OF(limit) = TYPE_INTEGER [
				int: as red-integer! limit
				int/value + input/head
			][
				unless all [
					TYPE_OF(limit) = TYPE_OF(input)
					limit/node = input/node
				][
					ERR_INVALID_REFINEMENT_ARG(refinements/_part limit)
				]
				limit/head
			]
			if part <= 0 [
				logic/box zero? either any [
					TYPE_OF(input) = TYPE_STRING		;@@ replace with ANY_STRING?
					TYPE_OF(input) = TYPE_FILE
					TYPE_OF(input) = TYPE_URL
				][
					string/rs-length? as red-string! input
				][
					block/rs-length? as red-block! input
				]
				return 0
			]
		]
		cframe: stack/get-ctop							;-- save the current call frame pointer
		
		catch RED_THROWN_BREAK [
			res: parser/process
				input
				as red-block! stack/arguments + 1
				op
				;as logic! strict? + 1
				part
				as red-function! stack/arguments + trace
		]
		switch system/thrown [
			RED_THROWN_BREAK
			RED_THROWN_CONTINUE
			RED_THROWN_RETURN
			RED_THROWN_EXIT [
				either stack/eval? cframe [				;-- if run from interpreter,
					re-throw 							;-- let the exception pass through
					0									;-- 0 to make compiler happy		
				][
					system/thrown						;-- request an early exit from caller
				]
			]
			0			[stack/set-last res 0]			;-- 0 to make compiler happy
			default 	[re-throw 0]					;-- 0 to make compiler happy
		]
	]

	do-set-op: func [
		cased	 [integer!]
		skip	 [integer!]
		op		 [integer!]
		/local
			set1	 [red-value!]
			skip-arg [red-value!]
			case?	 [logic!]
	][
		set1:	  stack/arguments
		skip-arg: set1 + skip
		case?:	  as logic! cased + 1
		
		switch TYPE_OF(set1) [
			TYPE_BLOCK   
			TYPE_HASH    [block/do-set-op case? as red-integer! skip-arg op]
			TYPE_STRING  [string/do-set-op case? as red-integer! skip-arg op]
			TYPE_BITSET  [bitset/do-bitwise op]
			TYPE_TYPESET [typeset/do-bitwise op]
			default 	 [ERR_EXPECT_ARGUMENT((TYPE_OF(set1)) 1)]
		]
	]
	
	union*: func [
		check? [logic!]
		cased  [integer!]
		skip   [integer!]
	][
		#typecheck [union cased skip]
		do-set-op cased skip OP_UNION
	]
	
	intersect*: func [
		check? [logic!]
		cased  [integer!]
		skip   [integer!]
	][
		#typecheck [intersect cased skip]
		do-set-op cased skip OP_INTERSECT
	]
	
	unique*: func [
		check? [logic!]
		cased  [integer!]
		skip   [integer!]
	][
		#typecheck [unique cased skip]
		do-set-op cased skip OP_UNIQUE
	]
	
	difference*: func [
		check? [logic!]
		cased  [integer!]
		skip   [integer!]
	][
		#typecheck [difference cased skip]
		do-set-op cased skip OP_DIFFERENCE
	]

	exclude*: func [
		check? [logic!]
		cased  [integer!]
		skip   [integer!]
	][
		#typecheck [exclude cased skip]
		do-set-op cased skip OP_EXCLUDE
	]

	complement?*: func [
		check?  [logic!]
		return: [red-logic!]
		/local
			bits   [red-bitset!]
			s	   [series!]
			result [red-logic!]
	][
		#typecheck complement
		bits: as red-bitset! stack/arguments
		s: GET_BUFFER(bits)
		result: as red-logic! bits

		either TYPE_OF(bits) =  TYPE_BITSET [
			result/value: s/flags and flag-bitset-not = flag-bitset-not
		][
			ERR_EXPECT_ARGUMENT((TYPE_OF(bits)) 1)
		]

		result/header: TYPE_LOGIC
		result
	]

	dehex*: func [
		check?  [logic!]
		return: [red-string!]
		/local
			str		[red-string!]
			buffer	[red-string!]
			s		[series!]
			p		[byte-ptr!]
			p4		[int-ptr!]
			tail	[byte-ptr!]
			unit	[integer!]
			cp		[integer!]
			len		[integer!]
	][
		#typecheck dehex
		str: as red-string! stack/arguments
		s: GET_BUFFER(str)
		unit: GET_UNIT(s)
		p: (as byte-ptr! s/offset) + (str/head << (log-b unit))
		tail: as byte-ptr! s/tail
		if p = tail [return str]						;-- empty string case

		len: string/rs-length? str
		stack/keep										;-- keep last value
		buffer: string/rs-make-at stack/push* len * unit

		while [p < tail][
			cp: switch unit [
				Latin1 [as-integer p/value]
				UCS-2  [(as-integer p/2) << 8 + p/1]
				UCS-4  [p4: as int-ptr! p p4/value]
			]

			p: p + unit
			if all [
				cp = as-integer #"%"
				p + (unit << 1) < tail					;-- must be %xx
			][
				p: string/decode-utf8-hex p unit :cp false
			]
			string/append-char GET_BUFFER(buffer) cp unit
		]
		stack/set-last as red-value! buffer
		buffer
	]

	debase*: func [
		check?   [logic!]
		base-arg [integer!]
		/local
			data [red-string!]
			int  [red-integer!]
			base [integer!]
			s	 [series!]
			p	 [byte-ptr!]
			len  [integer!]
			unit [integer!]
			ret  [red-binary!]
	][
		#typecheck [debase base-arg]
		data: as red-string! stack/arguments
		base: either positive? base-arg [
			int: as red-integer! data + 1
			int/value
		][64]

		s:  GET_BUFFER(data)
		unit: GET_UNIT(s)
		p:	  string/rs-head data
		len:  string/rs-length? data

		ret: as red-binary! data
		ret/head: 0
		ret/header: TYPE_BINARY
		ret/node: switch base [
			16 [binary/decode-16 p len unit]
			2  [binary/decode-2  p len unit]
			64 [binary/decode-64 p len unit]
			default [fire [TO_ERROR(script invalid-arg) int] null]
		]
		if ret/node = null [ret/header: TYPE_NONE]				;- RETURN_NONE
	]

	negative?*: func [
		check?  [logic!]
		return:	[red-logic!]
		/local
			num [red-integer!]
			f	[red-float!]
			res [red-logic!]
	][
		#typecheck -negative?-							;-- `negative?` would be replaced by lexer
		res: as red-logic! stack/arguments
		switch TYPE_OF(res) [							;@@ Add time! money! pair!
			TYPE_INTEGER [
				num: as red-integer! res
				res/value: negative? num/value
			]
			TYPE_FLOAT	 [
				f: as red-float! res
				res/value: f/value < 0.0
			]
			default [ERR_EXPECT_ARGUMENT((TYPE_OF(res)) 1)]
		]
		res/header: TYPE_LOGIC
		res
	]

	positive?*: func [
		check?  [logic!]
		return: [red-logic!]
		/local
			num [red-integer!]
			f	[red-float!]
			res [red-logic!]
	][
		#typecheck -positive?-							;-- `positive?` would be replaced by lexer
		res: as red-logic! stack/arguments
		switch TYPE_OF(res) [							;@@ Add time! money! pair!
			TYPE_INTEGER [
				num: as red-integer! res
				res/value: positive? num/value
			]
			TYPE_FLOAT	 [
				f: as red-float! res
				res/value: f/value > 0.0
			]
			default [ERR_EXPECT_ARGUMENT((TYPE_OF(res)) 1)]
		]
		res/header: TYPE_LOGIC
		res
	]

	max*: func [
		check? [logic!]
		/local
			args	[red-value!]
			result	[logic!]
	][
		#typecheck -max-								;-- `max` would be replaced by lexer
		args: stack/arguments
		result: actions/compare args args + 1 COMP_LESSER
		if result [
			stack/set-last args + 1
		]
	]

	min*: func [
		check? [logic!]
		/local
			args	[red-value!]
			result	[logic!]
	][
		#typecheck -min-								;-- `min` would be replaced by lexer
		args: stack/arguments
		result: actions/compare args args + 1 COMP_LESSER
		unless result [
			stack/set-last args + 1
		]
	]

	shift*: func [
		check?	[logic!]
		left	[integer!]
		logical	[integer!]
		/local
			data [red-integer!]
			bits [red-integer!]
	][
		#typecheck [shift left logical]
		data: as red-integer! stack/arguments
		bits: data + 1
		case [
			left >= 0 [
				data/value: data/value << bits/value
			]
			logical >= 0 [
				data/value: data/value >>> bits/value
			]
			true [
				data/value: data/value >> bits/value
			]
		]
	]

	to-hex*: func [
		check? [logic!]
		size   [integer!]
		/local
			arg	  [red-integer!]
			limit [red-integer!]
			buf   [red-word!]
			p	  [c-string!]
			part  [integer!]
	][
		#typecheck [to-hex size]
		arg: as red-integer! stack/arguments
		limit: arg + size

		p: string/to-hex arg/value no
		part: either OPTION?(limit) [8 - limit/value][0]
		if negative? part [part: 0]
		buf: issue/load p + part

		stack/set-last as red-value! buf
	]

	sine*: func [
		check?  [logic!]
		radians [integer!]
		/local
			f	[red-float!]
	][
		#typecheck [sine radians]
		f: degree-to-radians* radians TYPE_SINE
		f/value: sin f/value
		if DBL_EPSILON > float/abs f/value [f/value: 0.0]
		f
	]

	cosine*: func [
		check?  [logic!]
		radians [integer!]
		/local
			f	[red-float!]
	][
		#typecheck [cosine radians]
		f: degree-to-radians* radians TYPE_COSINE
		f/value: cos f/value
		if DBL_EPSILON > float/abs f/value [f/value: 0.0]
		f
	]

	tangent*: func [
		check?  [logic!]
		radians [integer!]
		/local
			f	[red-float!]
	][
		#typecheck [tangent radians]
		f: degree-to-radians* radians TYPE_TANGENT
		either (float/abs f/value) = (PI / 2.0) [
			fire [TO_ERROR(math overflow)]
		][
			f/value: tan f/value
		]
		f
	]

	arcsine*: func [
		check?  [logic!]
		radians [integer!]
		/local
			f	[red-float!]
	][
		#typecheck [arcsine radians]
		arc-trans radians TYPE_SINE
	]

	arccosine*: func [
		check?  [logic!]
		radians [integer!]
		/local
			f	[red-float!]
	][
		#typecheck [arccosine radians]
		arc-trans radians TYPE_COSINE
	]

	arctangent*: func [
		check?  [logic!]
		radians [integer!]
		/local
			f	[red-float!]
	][
		#typecheck [arctangent radians]
		arc-trans radians TYPE_TANGENT
	]

	arctangent2*: func [
		check? [logic!]
		/local
			f	[red-float!]
			n	[red-integer!]
			x	[float!]
			y	[float!]
	][
		#typecheck [arctangent2 radians]
		f: as red-float! stack/arguments 
		either TYPE_OF(f) <> TYPE_FLOAT [
			n: as red-integer! f
			y: integer/to-float n/value
		][
			y: f/value
		]
		f: as red-float! stack/arguments + 1
		either TYPE_OF(f) <> TYPE_FLOAT [
			n: as red-integer! f
			x: integer/to-float n/value
			f/header: TYPE_FLOAT
		][
			x: f/value
		]
		f/value: atan2 y x
		stack/set-last as red-value! f
	]

	NaN?*: func [
		check?  [logic!]
		return: [red-logic!]
		/local
			f	 [red-float!]
			ret  [red-logic!]
	][
		#typecheck NaN?
		f: as red-float! stack/arguments
		ret: as red-logic! f
		ret/value: float/NaN? f/value
		ret/header: TYPE_LOGIC
		ret
	]

	log-2*: func [
		check? [logic!]
		/local
			f  [red-float!]
	][
		#typecheck log-2
		f: argument-as-float
		f/value: (log f/value) / 0.6931471805599453
	]

	log-10*: func [
		check? [logic!]
		/local
			f  [red-float!]
	][
		#typecheck log-10
		f: argument-as-float
		f/value: log10 f/value
	]

	log-e*: func [
		check? [logic!]
		/local
			f  [red-float!]
	][
		#typecheck log-e
		f: argument-as-float
		f/value: log f/value
	]

	exp*: func [
		check? [logic!]
		/local
			f  [red-float!]
	][
		#typecheck exp
		f: argument-as-float
		f/value: pow 2.718281828459045235360287471 f/value
	]

	square-root*: func [
		check? [logic!]
		/local
			f  [red-float!]
	][
		#typecheck square-root
		f: argument-as-float
		f/value: sqrt f/value
	]
	
	construct*: func [
		check? [logic!]
		_with  [integer!]
		only   [integer!]
		/local
			proto [red-object!]
	][
		#typecheck [construct _with only]
		proto: either _with >= 0 [as red-object! stack/arguments + 1][null]
		
		stack/set-last as red-value! object/construct
			as red-block! stack/arguments
			proto
			only >= 0
	]

	value?*: func [
		check? [logic!]
		/local
			value  [red-value!]
			result [red-logic!]
	][
		#typecheck value?
		value: stack/arguments
		if TYPE_OF(value) = TYPE_WORD [
			value: _context/get as red-word! stack/arguments
		]
		result: as red-logic! stack/arguments
		result/value: TYPE_OF(value) <> TYPE_UNSET
		result/header: TYPE_LOGIC
		result
	]
	
	handle-thrown-error: func [
		/local
			err	[red-object!]
			id  [integer!]
	][
		err: as red-object! stack/top - 1
		assert TYPE_OF(err) = TYPE_ERROR
		id: error/get-type err
		either id = words/errors/throw/symbol [			;-- check if error is of type THROW
			re-throw 									;-- let the error pass through
		][
			stack/adjust-post-try
		]
	]
	
	try*: func [
		check?  [logic!]
		_all	[integer!]
		return: [integer!]
		/local
			arg	   [red-value!]
			cframe [byte-ptr!]
			err	   [red-object!]
			id	   [integer!]
			result [integer!]
	][
		#typecheck try
		arg: stack/arguments
		system/thrown: 0								;@@ To be removed
		cframe: stack/get-ctop							;-- save the current call frame pointer
		result: 0
		
		either _all = -1 [
			stack/mark-try words/_try
		][
			stack/mark-try-all words/_try
		]
		catch RED_THROWN_ERROR [
			interpreter/eval as red-block! arg yes
			stack/unwind-last							;-- bypass it in case of error
		]
		either _all = -1 [
			switch system/thrown [
				RED_THROWN_BREAK
				RED_THROWN_CONTINUE
				RED_THROWN_RETURN
				RED_THROWN_EXIT [
					either stack/eval? cframe [			;-- if run from interpreter,					
						re-throw 						;-- let the exception pass through
					][
						result: system/thrown			;-- request an early exit from caller
					]
				]
				RED_THROWN_ERROR [
					handle-thrown-error
				]
				0		[stack/adjust-post-try]
				default [re-throw]
			]
		][												;-- TRY/ALL case, catch everything
			stack/adjust-post-try
		]
		system/thrown: 0
		result
	]

	uppercase*: func [
		check? [logic!]
		part [integer!]
	][
		#typecheck [uppercase part]
		case-folding/change-case stack/arguments part yes
	]

	lowercase*: func [
		check? [logic!]
		part [integer!]
	][
		#typecheck [lowercase part]
		case-folding/change-case stack/arguments part no
	]
	
	as-pair*: func [
		check? [logic!]
		/local
			pair [red-pair!]
			arg	 [red-value!]
			int  [red-integer!]
			fl	 [red-float!]
	][
		#typecheck as-pair
		arg: stack/arguments
		pair: as red-pair! arg
		
		switch TYPE_OF(arg) [
			TYPE_INTEGER [
				int: as red-integer! arg
				pair/x: int/value
			]
			TYPE_FLOAT	 [
				fl: as red-float! arg
				pair/x: float/to-integer fl/value
			]
			default		 [assert false]
		]
		arg: arg + 1
		switch TYPE_OF(arg) [
			TYPE_INTEGER [
				int: as red-integer! arg
				pair/y: int/value
			]
			TYPE_FLOAT	 [
				fl: as red-float! arg
				pair/y: float/to-integer fl/value
			]
			default		[assert false]
		]
		pair/header: TYPE_PAIR
	]
	
	break*: func [check? [logic!] returned [integer!]][
		#typecheck [break returned]
		stack/throw-break returned <> -1 no
	]
	
	continue*: func [check? [logic!]][
		#typecheck continue
		stack/throw-break no yes
	]
	
	exit*: func [check? [logic!]][
		#typecheck exit
		stack/throw-exit no
	]
	
	return*: func [check? [logic!]][
		#typecheck return
		stack/throw-exit yes
	]
	
	throw*: func [
		check? [logic!]
		name   [integer!]
	][
		#typecheck [throw name]
		if name = -1 [unset/push]						;-- fill this slot anyway for CATCH		
		stack/throw-throw RED_THROWN_THROW
	]
	
	catch*: func [
		check? [logic!]
		name   [integer!]
		/local
			arg	   [red-value!]
			c-name [red-word!]
			t-name [red-word!]
			word   [red-word!]
			tail   [red-word!]
			id	   [integer!]
			found? [logic!]
	][
		#typecheck [catch name]
		found?: no
		id:		0
		arg:	stack/arguments
		
		if name <> -1 [
			c-name: as red-word! arg + name
			id: c-name/symbol
		]
		stack/mark-catch words/_body
		catch RED_THROWN_THROW [interpreter/eval as red-block! arg yes]
		t-name: as red-word! stack/arguments + 1
		stack/unwind-last
		
		if system/thrown > 0 [
			if system/thrown <> RED_THROWN_THROW [re-throw]
			if name <> -1 [
				either TYPE_OF(t-name) = TYPE_WORD [
					either TYPE_OF(c-name) = TYPE_BLOCK [
						word: as red-word! block/rs-head as red-block! c-name
						tail: as red-word! block/rs-tail as red-block! c-name
						while [word < tail][
							if TYPE_OF(word) <> TYPE_WORD [
								fire [TO_ERROR(script invalid-refine-arg) words/_name c-name]
							]
							if EQUAL_WORDS?(t-name word) [found?: yes break]
							word: word + 1
						]
					][
						found?: EQUAL_WORDS?(t-name c-name)
					]
				][
					found?: no							;-- THROW with no /NAME refinement
				]
				unless found? [
					copy-cell as red-value! t-name stack/arguments + 1 ;-- ensure t-name is at args + 1
					stack/ctop: stack/ctop - 1			;-- skip the current CATCH call frame
					stack/throw-throw RED_THROWN_THROW
				]
			]
			system/thrown: 0
			stack/set-last stack/top - 1
			stack/top: stack/arguments + 1
		]
	]
	
	extend*: func [
		check? [logic!]
		case?  [integer!]
		/local
			arg [red-value!]
	][
		#typecheck [extend case?]
		arg: stack/arguments
		switch TYPE_OF(arg) [
			TYPE_MAP 	[
				map/extend
					as red-hash! arg
					as red-block! arg + 1
					case? <> -1
			]
			TYPE_OBJECT [--NOT_IMPLEMENTED--]
		]
	]

	to-local-file*: func [
		check? [logic!]
		full?  [integer!]
		/local
			src  [red-file!]
			out  [red-string!]
	][
		#typecheck [to-local-file full?]
		src: as red-file! stack/arguments
		out: string/rs-make-at stack/push* string/rs-length? as red-string! src
		file/to-local-path src out full? <> -1
		stack/set-last as red-value! out
	]

	request-file*: func [
		check?  [logic!]
		title	[integer!]
		file	[integer!]
		filter	[integer!]
		save?	[integer!]
		multi?	[integer!]
	][
		#typecheck [request-file title file filter save? multi?]
		
		stack/set-last simple-io/request-file 
			as red-string! stack/arguments + title
			stack/arguments + file
			as red-block! stack/arguments + filter
			save? <> -1
			multi? <> -1
	]

	request-dir*: func [
		check?  [logic!]
		title	[integer!]
		dir		[integer!]
		filter	[integer!]
		keep?	[integer!]
		multi?	[integer!]
	][
		#typecheck [request-dir title dir filter keep? multi?]
		
		stack/set-last simple-io/request-dir 
			as red-string! stack/arguments + title
			stack/arguments + dir
			as red-block! stack/arguments + filter
			keep? <> -1
			multi? <> -1
	]

	wait*: func [
		check?	[logic!]
		all?	[integer!]
		only?	[integer!]
		/local
			val		[red-float!]
			int		[red-integer!]
			time	[integer!]
			ftime	[float!]
	][
		#typecheck [wait all? only?]
		val: as red-float! stack/arguments
		switch TYPE_OF(val) [
			TYPE_INTEGER [
				int: as red-integer! val
				time: int/value * #either OS = 'Windows [1000][1000000]
			]
			TYPE_FLOAT [
				ftime: val/value * #either OS = 'Windows [1000.0][1000000.0]
				if ftime < 1.0 [ftime: 1.0]
				time: float/to-integer ftime
			]
			default [fire [TO_ERROR(script invalid-arg) val]]
		]
		val/header: TYPE_NONE
		platform/wait time
	]

	;--- Natives helper functions ---

	argument-as-float: func [
		return: [red-float!]
		/local
			f	[red-float!]
			n	[red-integer!]
	][
		f: as red-float! stack/arguments
		if TYPE_OF(f) <> TYPE_FLOAT [
			f/header: TYPE_FLOAT
			n: as red-integer! f
			f/value: integer/to-float n/value
		]
		f
	]

	degree-to-radians*: func [
		radians [integer!]
		type	[integer!]
		return: [red-float!]
		/local
			f	[red-float!]
			val [float!]
	][
		f: argument-as-float
		val: f/value
		if radians < 0 [val: degree-to-radians val type]
		f/value: val
		f
	]

	arc-trans: func [
		radians [integer!]
		type	[integer!]
		return: [red-float!]
		/local
			f	[red-float!]
			d	[float!]
	][
		f: argument-as-float
		d: f/value

		either all [type <> TYPE_TANGENT any [d < -1.0 d > 1.0]] [
			fire [TO_ERROR(math overflow)]
		][
			f/value: switch type [
				TYPE_SINE	 [asin d]
				TYPE_COSINE  [acos d]
				TYPE_TANGENT [atan d]
			]
		]

		if radians < 0 [f/value: f/value * 180.0 / PI]			;-- to degrees
		f
	]

	loop?: func [
		series  [red-series!]
		return: [logic!]	
		/local
			s	 [series!]
			type [integer!]
			img  [red-image!]
	][
	
		type: TYPE_OF(series)
		if type = TYPE_IMAGE [
			img: as red-image! series
			return IMAGE_WIDTH(img/size) * IMAGE_HEIGHT(img/size) > img/head
		]
		s: GET_BUFFER(series)
		either any [									;@@ replace with any-block?
			type = TYPE_BLOCK
			type = TYPE_PAREN
			type = TYPE_PATH
			type = TYPE_GET_PATH
			type = TYPE_SET_PATH
			type = TYPE_LIT_PATH
		][
			s/offset + series/head < s/tail
		][
			(as byte-ptr! s/offset)
				+ (series/head << (log-b GET_UNIT(s)))
				< (as byte-ptr! s/tail)
		]
	]
	
	set-many: func [
		words [red-block!]
		value [red-value!]
		size  [integer!]
		only? [logic!]
		some? [logic!]
		/local
			w		[red-word!]
			v		[red-value!]
			blk		[red-block!]
			i		[integer!]
			type	[integer!]
			block?	[logic!]
	][
		i: 1
		type: TYPE_OF(value)
		block?: any [type = TYPE_BLOCK type = TYPE_HASH type = TYPE_MAP]
		if block? [blk: as red-block! value]
		
		while [i <= size][
			v: either all [block? not only?][_series/pick as red-series! blk i null][value]
			unless all [some? TYPE_OF(v) = TYPE_NONE][
				w: as red-word! _series/pick as red-series! words i null
				type: TYPE_OF(w)
				unless any [
					type = TYPE_WORD
					type = TYPE_GET_WORD
					type = TYPE_SET_WORD
					type = TYPE_LIT_WORD
				][
					fire [TO_ERROR(script invalid-arg) w]
				]
				_context/set w v
			]
			i: i + 1
		]
	]
	
	set-many-string: func [
		words [red-block!]
		str	  [red-string!]
		size  [integer!]
		/local
			v [red-value!]
			i [integer!]
	][
		i: 1
		while [i <= size][
			_context/set (as red-word! _series/pick as red-series! words i null) _series/pick as red-series! str i null
			i: i + 1
		]
	]

	foreach-next-block: func [
		size	[integer!]								;-- number of words in the block
		return: [logic!]
		/local
			series [red-series!]
			blk    [red-block!]
			type   [integer!]
			result [logic!]
	][
		blk:    as red-block!  stack/arguments - 1
		series: as red-series! stack/arguments - 2

		type: TYPE_OF(series)
		assert any [									;@@ replace with any-block?/any-string? check
			type = TYPE_BLOCK
			type = TYPE_HASH
			type = TYPE_PAREN
			type = TYPE_PATH
			type = TYPE_GET_PATH
			type = TYPE_SET_PATH
			type = TYPE_LIT_PATH
			type = TYPE_STRING
			type = TYPE_FILE
			type = TYPE_URL
			type = TYPE_VECTOR
			type = TYPE_BINARY
			type = TYPE_MAP
			type = TYPE_IMAGE
		]
		assert TYPE_OF(blk) = TYPE_BLOCK

		result: loop? series
		if result [
			switch type [
				TYPE_STRING
				TYPE_FILE
				TYPE_URL
				TYPE_VECTOR
				TYPE_BINARY [
					set-many-string blk as red-string! series size
				]
				TYPE_IMAGE [
					#either OS = 'Windows [
						image/set-many blk as red-image! series size
					][
						--NOT_IMPLEMENTED--
					]
				]
				default [
					set-many blk as red-value! series size no no
				]
			]
		]
		series/head: series/head + size
		result
	]
	
	foreach-next: func [
		return: [logic!]
		/local
			series [red-series!]
			word   [red-word!]
			result [logic!]
	][
		word:   as red-word!   stack/arguments - 1
		series: as red-series! stack/arguments - 2

		assert any [									;@@ replace with any-block?/any-string? check
			TYPE_OF(series) = TYPE_BLOCK
			TYPE_OF(series) = TYPE_HASH
			TYPE_OF(series) = TYPE_PAREN
			TYPE_OF(series) = TYPE_PATH
			TYPE_OF(series) = TYPE_GET_PATH
			TYPE_OF(series) = TYPE_SET_PATH
			TYPE_OF(series) = TYPE_LIT_PATH
			TYPE_OF(series) = TYPE_STRING
			TYPE_OF(series) = TYPE_FILE
			TYPE_OF(series) = TYPE_URL
			TYPE_OF(series) = TYPE_VECTOR
			TYPE_OF(series) = TYPE_BINARY
			TYPE_OF(series) = TYPE_MAP
			TYPE_OF(series) = TYPE_IMAGE
		]
		assert TYPE_OF(word) = TYPE_WORD
		
		result: loop? series
		if result [_context/set word actions/pick series 1 null]
		series/head: series/head + 1
		result
	]
	
	forall-loop: func [									;@@ inline?
		return: [logic!]
		/local
			series [red-series!]
			word   [red-word!]
	][
		word: as red-word! stack/arguments - 1
		assert TYPE_OF(word) = TYPE_WORD

		series: as red-series! _context/get word
		loop? series
	]
	
	forall-next: func [									;@@ inline?
		/local
			series [red-series!]
	][
		series: as red-series! _context/get as red-word! stack/arguments - 1
		series/head: series/head + 1
	]
	
	forall-end: func [									;@@ inline?
		/local
			series [red-series!]
			word   [red-word!]
	][
		word: 	as red-word!   stack/arguments - 1
		series: as red-series! stack/arguments - 2
		
		assert any [									;@@ replace with any-block?/any-string? check
			TYPE_OF(series) = TYPE_BLOCK
			TYPE_OF(series) = TYPE_HASH
			TYPE_OF(series) = TYPE_PAREN
			TYPE_OF(series) = TYPE_PATH
			TYPE_OF(series) = TYPE_GET_PATH
			TYPE_OF(series) = TYPE_SET_PATH
			TYPE_OF(series) = TYPE_LIT_PATH
			TYPE_OF(series) = TYPE_STRING
			TYPE_OF(series) = TYPE_FILE
			TYPE_OF(series) = TYPE_URL
			TYPE_OF(series) = TYPE_VECTOR
			TYPE_OF(series) = TYPE_BINARY
		]
		assert TYPE_OF(word) = TYPE_WORD

		_context/set word as red-value! series			;-- reset series to its initial offset
	]
	
	repeat-init*: func [
		cell  	[red-value!]
		return: [integer!]
		/local
			int [red-integer!]
	][
		copy-cell stack/arguments cell
		int: as red-integer! cell
		int/value										;-- overlapping /value field for integer! and char!
	]
	
	repeat-set: func [
		cell  [red-value!]
		value [integer!]
		/local
			int [red-integer!]
	][
		assert any [
			TYPE_OF(cell) = TYPE_INTEGER
			TYPE_OF(cell) = TYPE_CHAR
		]
		int: as red-integer! cell
		int/value: value								;-- overlapping /value field for integer! and char!
	]
	
	init: does [
		table: as int-ptr! allocate NATIVES_NB * size? integer!
		buffer-blk: block/make-in red/root 32			;-- block buffer for PRIN's reduce/into

		register [
			:if*
			:unless*
			:either*
			:any*
			:all*
			:while*
			:until*
			:loop*
			:repeat*
			:forever*
			:foreach*
			:forall*
			:func*
			:function*
			:does*
			:has*
			:switch*
			:case*
			:do*
			:get*
			:set*
			:print*
			:prin*
			:equal?*
			:not-equal?*
			:strict-equal?*
			:lesser?*
			:greater?*
			:lesser-or-equal?*
			:greater-or-equal?*
			:same?*
			:not*
			:type?*
			:reduce*
			:compose*
			:stats*
			:bind*
			:in*
			:parse*
			:union*
			:intersect*
			:unique*
			:difference*
			:exclude*
			:complement?*
			:dehex*
			:negative?*
			:positive?*
			:max*
			:min*
			:shift*
			:to-hex*
			:sine*
			:cosine*
			:tangent*
			:arcsine*
			:arccosine*
			:arctangent*
			:arctangent2*
			:NaN?*
			:log-2*
			:log-10*
			:log-e*
			:exp*
			:square-root*
			:construct*
			:value?*
			:try*
			:uppercase*
			:lowercase*
			:as-pair*
			:break*
			:continue*
			:exit*
			:return*
			:throw*
			:catch*
			:extend*
			:debase*
			:to-local-file*
			:request-file*
			:wait*
			:request-dir*
		]
	]

]
