vim9script

# Implement stacked menu (pum=true) and flat menu (pum=false)

export class PopupMenu
    var _winid: number
    var _bgWinId: number
    var _pum: bool
    var _selMatchId: number = 0
    var _items: list<any>
    var _index: number # index to items array
    var _hmenu = {text: '', ibegin: 0, iend: 0, selHiId: 0}

    def new(FilterFn: func(number, string): bool, CallbackFn: func(number, any), attributes: dict<any>, pum: bool)
        this._pum = pum
        if this._winid->popup_getoptions() == {} # popup does not exist
            var attr = {
                cursorline: false, # do not automatically select the first item
                pos: 'botleft',
                line: &lines - &cmdheight,
                col: 1,
                drag: false,
                border: [0, 0, 0, 0],
                filtermode: 'c',
                filter: FilterFn,
                hidden: true,
                callback: CallbackFn,
            }
            if pum
                attr->extend({ minwidth: 14 })
            else
                attr->extend({ scrollbar: 0, padding: [0, 0, 0, 0] })
            endif
            this._winid = popup_menu([], attr->extend(attributes))
        endif
        if !this._pum && this._bgWinId->popup_getoptions() == {}
            this._bgWinId = popup_create(' ', {line: &lines - &cmdheight, col: 1, minwidth: winwidth(0)})
        endif
    enddef

    def _Printify(): list<any>
        var items = this._items
        if items->len() <= 1
            def MakeDict(idx: number, v: string): dict<any>
                return {text: v}
            enddef
            return this._pum ? items[0]->mapnew(MakeDict) : [{text: this._hmenu.text}]
        endif
        if this._pum
            return items[0]->mapnew((idx, v) => {
                var mlen = items[2][idx]
                return {text: v, props: items[1][idx]->mapnew((_, c) => {
                    return {col: c + 1, length: mlen, type: 'VimSuggestMatch'}
                })}
            })
        else
            var offset = this._hmenu.offset + 1
            var props = []
            for idx in range(this._hmenu.ibegin, this._hmenu.iend)
                var word = items[0][idx]
                var pos = items[1][idx]
                var mlen = items[2][idx]
                for c in pos
                    var colnum = c + offset
                    props->add({col: colnum, length: mlen, type: 'VimSuggestMatch'})
                endfor
                offset += word->len() + 2
            endfor
            return [{text: this._hmenu.text, props: props}]
        endif
    enddef

    def _ClearMatches()
        this._winid->clearmatches()
        this._hmenu.selHiId = 0
        this._selMatchId = 0
    enddef

    def SetText(items: list<any>, moveto: number = 0)
        this._items = items
        this._ClearMatches()
        if this._pum
            if moveto > 0
                this._winid->popup_move({col: moveto})
            endif
            this._winid->popup_settext(this._Printify())
            win_execute(this._winid, "normal! gg")
        else
            this._HMenu(0, 'left')
            try
                this._winid->popup_settext(this._Printify())
            catch /^Vim\%((\a\+)\)\=:E964:/ # Vim throws E964 occasionally when non-ascii wide chars are present
            endtry
        endif
        this._index = -1
        this._winid->popup_setoptions({cursorline: false})
        this._selMatchId = 0
    enddef

    def _HMenu(startidx: number, position: string)
        const items = this._items
        const words = items[0]
        var selected = [words[startidx]]
        var atleft = position ==# 'left'
        var overflowl = startidx > 0
        var overflowr = startidx < words->len() - 1
        var idx = startidx
        var hmenuMaxWidth = winwidth(0) - 4
        while (atleft && idx < words->len() - 1) ||
                (!atleft && idx > 0)
            idx += (atleft ? 1 : -1)
            var last = (atleft ? idx == words->len() - 1 : idx == 0)
            if selected->join('  ')->len() + words[idx]->len() + 1 <
                    hmenuMaxWidth - (last ? 0 : 4)
                if atleft
                    selected->add(words[idx])
                else
                    selected->insert(words[idx])
                endif
            else
                idx -= (atleft ? 1 : -1)
                break
            endif
        endwhile
        if atleft
            overflowr = idx < words->len() - 1
        else
            overflowl = idx > 0
        endif
        var htext = (overflowl ? '< ' : '') .. selected->join('  ') .. (overflowr ? ' >' : '')
        this._hmenu->extend({text: htext, ibegin: atleft ? startidx : idx, iend: atleft ? idx : startidx, offset: overflowl ? 2 : 0})
    enddef

    # select next/prev item in popup menu; wrap around at end of list
    def SelectItem(direction: string, CallbackFn: func(number))
        const count = this._items[0]->len()
        const items = this._items

        def SelectVert()
            if this._winid->popup_getoptions().cursorline
                this._winid->popup_filter_menu(direction)
                this._index += (direction ==# 'j' ? 1 : -1)
                this._index %= count
            else
                this._winid->popup_setoptions({cursorline: true})
                this._index = 0
            endif
            if items->len() > 1
                var mlen = items[2][this._index]
                if items->len() > 1
                    var pos = items[1][this._index]->mapnew((_, v) => [this._index + 1, v + 1, mlen])
                    if !pos->empty()
                        this._selMatchId = matchaddpos('VimSuggestMatchSel', pos, 13, -1, {window: this._winid})
                    endif
                endif
            endif
        enddef

        def SelectHoriz()
            var rotate = false
            if this._index == -1
                this._index = direction ==# 'j' ? 0 : count - 1
                rotate = true
            else
                if this._index == (direction ==# 'j' ? count - 1 : 0)
                    this._index = (direction ==# 'j' ? 0 : count - 1)
                    rotate = true
                else
                    this._index += (direction ==# 'j' ? 1 : -1)
                endif
            endif
            if this._index < this._hmenu.ibegin || this._index > this._hmenu.iend
                if direction ==# 'j'
                    this._HMenu(rotate ? 0 : this._index, rotate ? 'left' : 'right')
                else
                    this._HMenu(rotate ? count - 1 : this._index, rotate ? 'right' : 'left')
                endif
                this._ClearMatches()
                this._winid->popup_settext(this._Printify())
            endif

            # highlight selected word
            if this._hmenu.selHiId > 0
                matchdelete(this._hmenu.selHiId, this._winid)
                this._hmenu.selHiId = 0
            endif
            var offset = 1 + this._hmenu.offset
            if this._index > 0
                offset += items[0][this._hmenu.ibegin : this._index - 1]->reduce((acc, v) => acc + v->len() + 2, 0)
            endif
            this._hmenu.selHiId = matchaddpos(hlexists('PopupSelected') ? 'PopupSelected' : 'PmenuSel',
                [[1, offset, items[0][this._index]->len()]], 12, -1, {window: this._winid})

            # highlight matched pattern of selected word
            if items->len() > 1
                var mlen = items[2][this._index]
                var pos = items[1][this._index]->mapnew((_, v) => [1, v + offset, mlen])
                if !pos->empty()
                    this._selMatchId = matchaddpos('VimSuggestMatchSel', pos, 13, -1, {window: this._winid})
                endif
            endif
        enddef

        if this._selMatchId > 0
            matchdelete(this._selMatchId, this._winid)
            this._selMatchId = 0
        endif

        this._pum ? SelectVert() : SelectHoriz()
        if CallbackFn != null_function
            CallbackFn(this._index)
        endif
    enddef

    def Close()
        if this._winid->popup_getoptions() != {} # popup exists
            this._winid->popup_close()
        endif
        if !this._pum && this._bgWinId->popup_getoptions() != {}
            this._bgWinId->popup_close()
        endif
    enddef

    def Show()
        this._winid->popup_show()
    enddef

    def Hide()
        this._winid->popup_hide()
    enddef
endclass