" Tests for the terminal window.

if !exists('*term_start')
  finish
endif

source shared.vim

let s:python = PythonProg()

" Open a terminal with a shell, assign the job to g:job and return the buffer
" number.
func Run_shell_in_terminal(options)
  let buf = term_start(&shell, a:options)

  let termlist = term_list()
  call assert_equal(1, len(termlist))
  call assert_equal(buf, termlist[0])

  let g:job = term_getjob(buf)
  call assert_equal(v:t_job, type(g:job))

  let string = string({'job': term_getjob(buf)})
  call assert_match("{'job': 'process \\d\\+ run'}", string)

  return buf
endfunc

" Stops the shell started by Run_shell_in_terminal().
func Stop_shell_in_terminal(buf)
  call term_sendkeys(a:buf, "exit\r")
  call WaitFor('job_status(g:job) == "dead"')
  call assert_equal('dead', job_status(g:job))
endfunc

func Test_terminal_basic()
  let buf = Run_shell_in_terminal({})
  if has("unix")
    call assert_match("^/dev/", job_info(g:job).tty)
    call assert_match("^/dev/", term_gettty(''))
  else
    call assert_match("^winpty://", job_info(g:job).tty)
    call assert_match("^winpty://", term_gettty(''))
  endif
  call Stop_shell_in_terminal(buf)
  call term_wait(buf)

  " closing window wipes out the terminal buffer a with finished job
  close
  call assert_equal("", bufname(buf))

  unlet g:job
endfunc

func Test_terminal_make_change()
  let buf = Run_shell_in_terminal({})
  call Stop_shell_in_terminal(buf)
  call term_wait(buf)

  setlocal modifiable
  exe "normal Axxx\<Esc>"
  call assert_fails(buf . 'bwipe', 'E517')
  undo

  exe buf . 'bwipe'
  unlet g:job
endfunc

func Test_terminal_wipe_buffer()
  let buf = Run_shell_in_terminal({})
  call assert_fails(buf . 'bwipe', 'E517')
  exe buf . 'bwipe!'
  call WaitFor('job_status(g:job) == "dead"')
  call assert_equal('dead', job_status(g:job))
  call assert_equal("", bufname(buf))

  unlet g:job
endfunc

func Test_terminal_hide_buffer()
  let buf = Run_shell_in_terminal({})
  quit
  for nr in range(1, winnr('$'))
    call assert_notequal(winbufnr(nr), buf)
  endfor
  call assert_true(bufloaded(buf))
  call assert_true(buflisted(buf))

  exe 'split ' . buf . 'buf'
  call Stop_shell_in_terminal(buf)
  exe buf . 'bwipe'

  unlet g:job
endfunc

func! s:Nasty_exit_cb(job, st)
  exe g:buf . 'bwipe!'
  let g:buf = 0
endfunc

func Test_terminal_nasty_cb()
  let cmd = Get_cat_123_cmd()
  let g:buf = term_start(cmd, {'exit_cb': function('s:Nasty_exit_cb')})
  let g:job = term_getjob(g:buf)

  call WaitFor('job_status(g:job) == "dead"')
  call WaitFor('g:buf == 0')
  unlet g:buf
  unlet g:job
  call delete('Xtext')
endfunc

func Check_123(buf)
  let l = term_scrape(a:buf, 0)
  call assert_true(len(l) == 0)
  let l = term_scrape(a:buf, 999)
  call assert_true(len(l) == 0)
  let l = term_scrape(a:buf, 1)
  call assert_true(len(l) > 0)
  call assert_equal('1', l[0].chars)
  call assert_equal('2', l[1].chars)
  call assert_equal('3', l[2].chars)
  call assert_equal('#00e000', l[0].fg)
  if &background == 'light'
    call assert_equal('#ffffff', l[0].bg)
  else
    call assert_equal('#000000', l[0].bg)
  endif

  let l = term_getline(a:buf, -1)
  call assert_equal('', l)
  let l = term_getline(a:buf, 0)
  call assert_equal('', l)
  let l = term_getline(a:buf, 999)
  call assert_equal('', l)
  let l = term_getline(a:buf, 1)
  call assert_equal('123', l)
endfunc

func Get_cat_123_cmd()
  if has('win32')
    return 'cmd /c "cls && color 2 && echo 123"'
  else
    call writefile(["\<Esc>[32m123"], 'Xtext')
    return "cat Xtext"
  endif
endfunc

func Test_terminal_scrape_123()
  let cmd = Get_cat_123_cmd()
  let buf = term_start(cmd)

  let termlist = term_list()
  call assert_equal(1, len(termlist))
  call assert_equal(buf, termlist[0])

  " Nothing happens with invalid buffer number
  call term_wait(1234)

  call term_wait(buf)
  if has('win32')
    " TODO: this should not be needed
    sleep 100m
  endif
  call Check_123(buf)

  " Must still work after the job ended.
  let g:job = term_getjob(buf)
  call WaitFor('job_status(g:job) == "dead"')
  call term_wait(buf)
  call Check_123(buf)

  exe buf . 'bwipe'
  call delete('Xtext')
endfunc

func Test_terminal_scrape_multibyte()
  if !has('multi_byte')
    return
  endif
  call writefile(["léttまrs"], 'Xtext')
  if has('win32')
    let cmd = 'cmd /c "type Xtext"'
  else
    let cmd = "cat Xtext"
  endif
  let buf = term_start(cmd)

  call term_wait(buf)
  if has('win32')
    " TODO: this should not be needed
    sleep 100m
  endif

  let l = term_scrape(buf, 1)
  call assert_true(len(l) >= 7)
  call assert_equal('l', l[0].chars)
  call assert_equal('é', l[1].chars)
  call assert_equal(1, l[1].width)
  call assert_equal('t', l[2].chars)
  call assert_equal('t', l[3].chars)
  call assert_equal('ま', l[4].chars)
  call assert_equal(2, l[4].width)
  call assert_equal('r', l[5].chars)
  call assert_equal('s', l[6].chars)

  let g:job = term_getjob(buf)
  call WaitFor('job_status(g:job) == "dead"')
  call term_wait(buf)

  exe buf . 'bwipe'
  call delete('Xtext')
endfunc

func Test_terminal_scroll()
  call writefile(range(1, 200), 'Xtext')
  if has('win32')
    let cmd = 'cmd /c "type Xtext"'
  else
    let cmd = "cat Xtext"
  endif
  let buf = term_start(cmd)

  let g:job = term_getjob(buf)
  call WaitFor('job_status(g:job) == "dead"')
  call term_wait(buf)
  if has('win32')
    " TODO: this should not be needed
    sleep 100m
  endif

  let scrolled = term_getscrolled(buf)
  call assert_equal('1', getline(1))
  call assert_equal('1', term_getline(buf, 1 - scrolled))
  call assert_equal('49', getline(49))
  call assert_equal('49', term_getline(buf, 49 - scrolled))
  call assert_equal('200', getline(200))
  call assert_equal('200', term_getline(buf, 200 - scrolled))

  exe buf . 'bwipe'
  call delete('Xtext')
endfunc

func Test_terminal_size()
  let cmd = Get_cat_123_cmd()

  exe '5terminal ' . cmd
  let size = term_getsize('')
  bwipe!
  call assert_equal(5, size[0])

  call term_start(cmd, {'term_rows': 6})
  let size = term_getsize('')
  bwipe!
  call assert_equal(6, size[0])

  vsplit
  exe '5,33terminal ' . cmd
  let size = term_getsize('')
  bwipe!
  call assert_equal([5, 33], size)

  call term_start(cmd, {'term_rows': 6, 'term_cols': 36})
  let size = term_getsize('')
  bwipe!
  call assert_equal([6, 36], size)

  exe 'vertical 20terminal ' . cmd
  let size = term_getsize('')
  bwipe!
  call assert_equal(20, size[1])

  call term_start(cmd, {'vertical': 1, 'term_cols': 26})
  let size = term_getsize('')
  bwipe!
  call assert_equal(26, size[1])

  split
  exe 'vertical 6,20terminal ' . cmd
  let size = term_getsize('')
  bwipe!
  call assert_equal([6, 20], size)

  call term_start(cmd, {'vertical': 1, 'term_rows': 7, 'term_cols': 27})
  let size = term_getsize('')
  bwipe!
  call assert_equal([7, 27], size)
endfunc

func Test_terminal_curwin()
  let cmd = Get_cat_123_cmd()
  call assert_equal(1, winnr('$'))

  split dummy
  exe 'terminal ++curwin ' . cmd
  call assert_equal(2, winnr('$'))
  bwipe!

  split dummy
  call term_start(cmd, {'curwin': 1})
  call assert_equal(2, winnr('$'))
  bwipe!

  split dummy
  call setline(1, 'change')
  call assert_fails('terminal ++curwin ' . cmd, 'E37:')
  call assert_equal(2, winnr('$'))
  exe 'terminal! ++curwin ' . cmd
  call assert_equal(2, winnr('$'))
  bwipe!

  split dummy
  call setline(1, 'change')
  call assert_fails("call term_start(cmd, {'curwin': 1})", 'E37:')
  call assert_equal(2, winnr('$'))
  bwipe!

  split dummy
  bwipe!

endfunc

func Test_finish_open_close()
  call assert_equal(1, winnr('$'))

  if s:python != ''
    let cmd = s:python . " test_short_sleep.py"
    let waittime = 500
  else
    echo 'This will take five seconds...'
    let waittime = 2000
    if has('win32')
      let cmd = $windir . '\system32\timeout.exe 1'
    else
      let cmd = 'sleep 1'
    endif
  endif

  exe 'terminal ++close ' . cmd
  call assert_equal(2, winnr('$'))
  wincmd p
  call WaitFor("winnr('$') == 1", waittime)
  call assert_equal(1, winnr('$'))

  call term_start(cmd, {'term_finish': 'close'})
  call assert_equal(2, winnr('$'))
  wincmd p
  call WaitFor("winnr('$') == 1", waittime)
  call assert_equal(1, winnr('$'))

  exe 'terminal ++open ' . cmd
  close
  call WaitFor("winnr('$') == 2", waittime)
  call assert_equal(2, winnr('$'))
  bwipe

  call term_start(cmd, {'term_finish': 'open'})
  close
  call WaitFor("winnr('$') == 2", waittime)
  call assert_equal(2, winnr('$'))
  bwipe

  exe 'terminal ++hidden ++open ' . cmd
  call assert_equal(1, winnr('$'))
  call WaitFor("winnr('$') == 2", waittime)
  call assert_equal(2, winnr('$'))
  bwipe

  call term_start(cmd, {'term_finish': 'open', 'hidden': 1})
  call assert_equal(1, winnr('$'))
  call WaitFor("winnr('$') == 2", waittime)
  call assert_equal(2, winnr('$'))
  bwipe

  call assert_fails("call term_start(cmd, {'term_opencmd': 'open'})", 'E475:')
  call assert_fails("call term_start(cmd, {'term_opencmd': 'split %x'})", 'E475:')
  call assert_fails("call term_start(cmd, {'term_opencmd': 'split %d and %s'})", 'E475:')
  call assert_fails("call term_start(cmd, {'term_opencmd': 'split % and %d'})", 'E475:')

  call term_start(cmd, {'term_finish': 'open', 'term_opencmd': '4split | buffer %d'})
  close
  call WaitFor("winnr('$') == 2", waittime)
  call assert_equal(2, winnr('$'))
  call assert_equal(4, winheight(0))
  bwipe

endfunc

func Test_terminal_cwd()
  if !has('unix')
    return
  endif
  call mkdir('Xdir')
  let buf = term_start('pwd', {'cwd': 'Xdir'})
  sleep 100m
  call term_wait(buf)
  call assert_equal(getcwd() . '/Xdir', getline(1))

  exe buf . 'bwipe'
  call delete('Xdir', 'rf')
endfunc

func Test_terminal_env()
  if !has('unix')
    return
  endif
  let buf = Run_shell_in_terminal({'env': {'TESTENV': 'correct'}})
  call term_wait(buf)
  call term_sendkeys(buf, "echo $TESTENV\r")
  call term_wait(buf)
  call Stop_shell_in_terminal(buf)
  call term_wait(buf)
  call assert_equal('correct', getline(2))

  exe buf . 'bwipe'
endfunc
