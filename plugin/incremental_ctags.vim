

let s:path = expand('<sfile>:p:h')
let s:generate_ctags_shell = s:path."/../generate_ctags.sh"

function!BackgroundCommandClose(channel)
 execute ':bd IncrementalCTags'
endfunction

function! RunBackgroundCommand(command)
    call job_start(a:command, {'close_cb': 'BackgroundCommandClose', 'out_io': 'buffer', 'out_name': 'IncrementalCTags'})
    split | buffer IncrementalCTags
endfunction

function! GenerateCtags()
  if v:version < 800 " job_start is not supported for versions less than 800
    execute '!bash '.s:generate_ctags_shell
  else
    call RunBackgroundCommand('bash '.s:generate_ctags_shell)
  endif
endfunction


:command IncrementalCtagsUpdate call GenerateCtags()

function TagFunc(pattern, flags, info)
  let tags_list = []
  let sqlite_db = trim(system('echo $HOME/.ctags_cache/$(git rev-parse --show-toplevel)/tags.sqlite'))
  if !filereadable(sqlite_db)
    return []
  endif
  let select_query = 'Select name, filename, cmd, kind from TAGS where name == "' . a:pattern . '";'
  if strridx(a:flags, 'i') != -1
    let new_pattern = substitute(a:pattern, '\\<', '', 'g')
    let select_query = 'Select name, filename, cmd, kind from TAGS where name like "' . new_pattern . '";'
  endif
  echom 'Query: '.select_query
  let cmd = 'sqlite3 '.sqlite_db." '".select_query."'"
  let query_result = systemlist(cmd)
  for result in query_result
    echom 'Result: '.result
    let columns = split(result, '|')
    let entry = { 'name': columns[0], 'filename': columns[1], 'cmd': columns[2] }
    " the if condition because a bug in generation code
    if len(columns) >= 4
      let entry.kind = columns[3]
    endif
    call add(tags_list, entry)
  endfor
  echom "Number of tags got:".len(tags_list)
  return tags_list
endfunc

set tagfunc=TagFunc
