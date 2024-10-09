vim9script

import autoload '../cmd.vim'
import autoload './job.vim'

var items: list<any>
var candidate: string
var exit_key: string
var hooks_added: dict<any>

export def Clear()
    items = []
    candidate = null_string
    exit_key = null_string
enddef

# Usage:
# :<Command> Shell_cmd Shell_cmd_arg1 Shell_cmd_arg2 ...
# :<Command> <pattern>
export def Complete(context: string, line: string, cursorpos: number,
        async = true, timeout = 2000, max_items = 1000): list<any>
    # Note: Both 'context' and 'line' arg contains text up to 'cursorpos' only.
    Clear()
    var parts = cmd.CmdStr()->split()
    if parts->len() > 1
        # Note: 'expandcmd' expands '~/path', but removes '\'. Use it minimally.
        var cstr = parts[1 : ]->mapnew((_, v) => v =~ '[~$]' ? expandcmd(v) : v)->join(' ')
        var shellprefix = expand("$SHELL") != null_string ? $'{expand("$SHELL")} -c' : ''
        return CompletionItems(cstr, shellprefix, async, timeout, max_items)
    endif
    return []
enddef

export def GrepComplete(A: string, L: string, C: number, shellprefix = null_string,
        async = true, timeout = 2000, max_items = 1000): list<any>
    Clear()
    var cmdstr = get(g:, 'vimsuggest_grepprg', &grepprg)
    var argstr = cmd.CmdStr()->matchstr('^\s*\S\+\s\+\zs.*$')
    # echom $'{argstr}|' 'argstr' $'{cmd.CmdStr()}|' 'full' $'{getcmdline()}|'
    if cmdstr != null_string && argstr->Strip() != null_string
        var parts = cmdstr->split('$\*')
        var cstr = $'{parts[0]} {argstr}{parts->len() == 2 ? $" {parts[1]}" : ""}'
        var itemss = CompletionItems(cstr, shellprefix, async, timeout, max_items)
        # Extract quoted or space escaped string to highlight (rest is dir path).
        # for pat in ['([^'']*)', '^''\zs.\{-}''\ze', '^"\zs.\{-}\(\\\)\@<!\ze"',

        # ary\ '
        var arglead = argstr->matchstr(MatchPattern())

            # '^"\zs\([^"\\]*\(\\"[^"\\]*\)*\)\ze"'
            # '^''\zs\([^'']*\(''''[^'']*\)*\)\ze'''
            #     '\%(\\ \|[^ ]\)\+']
        #     arglead = argstr->matchstr(pat)
        #     if arglead != null_string
        #         break
        #     endif
        # endfor
        if arglead != null_string
            var cmdlead = cmd.CmdLead()
            cmd.AddHighlightHook(cmdlead, (_: string, itms: list<any>): list<any> => {
                DoHighlight(arglead)
                return [itms]
            })
        endif
        return itemss
    endif
    return []
enddef

# export def FindComplete(A: string, L: string, C: number): list<any>
#     var cmdstr = get(g:, 'vimsuggest_findprg', null_string)
#     if cmdstr != null_string
#         cmdstr = (cmdstr->split('$\*')->len() == 2) ? $'{cmdstr} $*' : cmdstr
#         return exec.Complete(A, L, C, cmdstr)
#     endif
#     Clear()
#     return []
#         var argstr = cmd.CmdStr()->matchstr('^\s*\S\+\s\+\zs.*')
#         if cmd.Strip(argstr) != null_string
#             var arglist = argstr->split()
#             var parts = cmdstr->split('$\*')
#             if parts->len() > 2  # vimsuggest_findprg
#                 arglist = arglist->len() == 1 ? (arglist + ['.']) : arglist
#                 cstr = $'{parts[0]} {arglist[1 : ]->join(" ")} {parts[1]} {arglist[0]}' ..
#                     (parts->len() > 2 ? $' {parts[2]}' : '')
#             else
#                 cstr = $'{parts[0]} {argstr}{parts->len() == 2 ? $" {parts[1]}" : ""}'
#             endif
#         endif

# enddef

export def CompletionItems(cmdstr = null_string, shellprefix = null_string,
        async = true, timeout = 2000, max_items = 1000): list<any>
    if cmdstr != null_string
        if async
            var cmdany = shellprefix == null_string ? cmdstr : shellprefix->split() + [cmdstr]
            def ProcessItems(itms: list<any>)
                cmd.SetPopupMenu(itms)
                items = itms
            enddef
            job.Start(cmdany, ProcessItems, timeout, max_items)
        else
            try
                items = systemlist($'{shellprefix} {cmdstr}')
            catch  # '\' and '"' cause E282
            endtry
        endif
    endif
    var cmdlead = cmd.CmdLead()
    if !hooks_added->has_key(cmdlead)
        hooks_added[cmdlead] = 1
        AddHooks(cmdlead)
    endif
    return items
enddef

# Usage:
# :<Command> Shell_cmd Shell_cmd_arg1 Shell_cmd_arg2 ...
# :<Command> <pattern>
export def DoAction(ActionFn: func(string, string), arg1: string = '',
        arg2: string = '', arg3: string = '', arg4: string = '',
        arg5: string = '', arg6: string = '', arg7: string = '',
        arg8: string = '', arg9: string = '', arg10: string = '',
        arg11: string = '', arg12: string = '', arg13: string = '',
        arg14: string = '', arg15: string = '', arg16: string = '',
        arg17: string = '', arg18: string = '', arg19: string = '',
        arg20: string = '')
    if candidate != null_string
        if ActionFn != null_function
            ActionFn(candidate, exit_key)
        else
            DefaultAction(candidate, exit_key)
        endif
    endif
enddef

export def DefaultAction(tgt: string, key: string)
    if tgt->filereadable()
        VisitFile(key, tgt)
    else  # Assume 'tgt' is a 'grep' output line
        GrepVisitFile(key, tgt)
    endif
enddef

# Pattern to match everything inside quotes including " and ' escaped as \" and '',
# and to match space escaped non-quoted text.
def MatchPattern(): string
  return '\%(^"\zs\([^"\\]*\(\\"[^"\\]*\)*\)\ze"\|^''\zs\([^'']*\(''''[^'']*\)*\)\ze''\|\%(\\ \|[^ ]\)\+\)'
enddef

# Extract file from grep output and edit it.
# Let quicfix parse output of 'grep' for filename, line, column. It deals with
# ':' in filename and other corner cases.
export def GrepVisitFile(key: string, line: string)
    var qfitem = getqflist({lines: [line]}).items[0]
    if qfitem->has_key('bufnr')
        VisitBuffer(key, qfitem.bufnr, qfitem.lnum, qfitem.col, qfitem.vcol > 0)
        if !qfitem.bufnr->getbufvar('&buflisted') # getqflist keeps buffer unlisted
            setbufvar(qfitem.bufnr, '&buflisted', 1)
        endif
    endif
enddef

export def VisitBuffer(key: string, bufnr: number, lnum = -1, col = -1, visualcol = false)
    var keymap = {"\<C-j>": 'sb', "\<C-v>": 'vert sb', "\<C-t>": 'tab sb'}
    var cmdstr = keymap->get(key, 'b')
    if lnum > 0
        if col > 0
            var pos = visualcol ? 'setcharpos' : 'setpos'
            cmdstr = $'{cmdstr} +call\ {pos}(".",\ [0,\ {lnum},\ {col},\ 0])'
        else
            cmdstr = $'{cmdstr} +{lnum}'
        endif
    endif
    :exe $":{cmdstr} {bufnr}"
enddef

export def VisitFile(key: string, filename: string, lnum: number = -1)
    var keymap = {"\<C-j>": 'split', "\<C-v>": 'vert split', "\<C-t>": 'tabe'}
    if lnum > 0
        exe $":{keymap->get(key, 'e')} +{lnum} {filename}"
    else
        exe $":{keymap->get(key, 'e')} {filename}"
    endif
enddef

def Strip(pat: string): string
    # Remove " and ' around pattern, if any.
    var p = pat->substitute('^"', '', '')->substitute('"$', '', '')
    if p ==# pat
        p = p->substitute("^'", '', '')->substitute("'$", '', '')
    endif
    return p
enddef

def AddHooks(name: string)
    if !cmd.ValidState()
        return  # After <c-s>, cmd 'state' object has been removed
    endif
    cmd.AddCmdlineLeaveHook(name, (selected_item, first_item, key) => {
        candidate = selected_item == null_string ? first_item : selected_item
        exit_key = key
    })
    cmd.AddSelectItemHook(name, (_) => {
        return true # Do not update cmdline with selected item
    })
    # def MatchGrepLine(line: string, pat: string): list<any> # Match grep output
    #     var p = pat->Strip()
    #     return line->matchstrpos($'.*:.\{{-}}\zs{p}')  # Remove filename, linenum, and colnum
    # enddef
    # cmd.AddHighlightHook(name, (suffix: string, itms: list<any>): list<any> => {
    #     # grep command can have a dir argument at the end. Match only what is before the cursor.
    #     if suffix->Strip() != null_string && !itms->empty()
    #         return cmd.Highlight(suffix, itms,
    #             itms[0]->filereadable() ? null_function : MatchGrepLine)
    #     endif
    #     return [itms]
    # })
    cmd.AddHighlightHook(name, (arglead: string, itms: list<any>): list<any> => {
        DoHighlight(arglead)
        return [itms]
    })
    # cmd.AddNoExcludeHook(name)
enddef

export def DoHighlight(pattern: string, ignorecase = true)
    win_execute(cmd.state.pmenu.Winid(), "syn clear VimSuggestMatch")
    if pattern != null_string
        # var pat = Escape4Highlight(pattern)
        var pat = pattern
        # echom $'{pat}|'
        try
            if ignorecase
                win_execute(cmd.state.pmenu.Winid(), $"syn match VimSuggestMatch \"\\c{pat}\"")
            else
                win_execute(cmd.state.pmenu.Winid(), $"syn match VimSuggestMatch \"{pat}\"")
            endif
        catch # ignore any rogue exceptions.
        endtry
    endif
enddef

export def Escape4Highlight(s: string): string
    var pat = s->escape('~.[$^"')
    if pat[-1] == '\'
        pat = $'{pat}\'
    endif
    return pat
enddef

cmd.AddCmdlineEnterHook(() => {
    hooks_added = {}
})

:defcompile

# vim: tabstop=8 shiftwidth=4 softtabstop=4 expandtab
