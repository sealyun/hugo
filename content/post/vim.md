+++
author = "fanux"
date = "2019-01-23T10:54:24+02:00"
draft = false
title = "是时候表现一下我的vim了"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)
探讨可加QQ群：98488045

# 使用vim作golang开发
分享一些我使用的vim插件，以及制作过程，最终的功能有：

* golang开发，补全，跳转，文件列表，函数列表等
* kubernetes插件，方便写yaml文件
* 好看的颜色主题

先睹为快：

![](/vim.png)

再不总结下下次我又忘记了

# 安装macvim
主要是YouCompleteMe mac系统上需要依赖这个[地址](https://github.com/macvim-dev/macvim/releases)

非mac环境我会提供一个docker镜像

# 安装插件管理器vundle
```
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
```

我的~/.vimrc
```
set nocompatible              " be iMproved, required
" 🔑  (key)
let mapleader=","
filetype off "required

set foldmethod=indent

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" The following are examples of different formats supported.
" Keep Plugin commands between vundle#begin/end.
" plugin on GitHub repo
" Plugin 'tpope/vim-fugitive'
" plugin from http://vim-scripts.org/vim/scripts.html
Plugin 'L9'
" The sparkup vim script is in a subdirectory of this repo called vim.
" Pass the path to set the runtimepath properly.
" Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}
" Plugin 'nsf/gocode',{'rtp':'vim/'}
Plugin 'fatih/vim-go'
Bundle 'scrooloose/nerdtree'
"Bundle 'cespare/vim-golang'
" Bundle 'dgryski/vim-godef'
Plugin 'Valloric/YouCompleteMe'
" Plugin 'SirVer/ultisnips'
" Plugin 'majutsushi/tagbar'
Plugin 'vim-scripts/taglist.vim'
" Plugin 'junegunn/vim-emoji'
" Plugin 'rjohnsondev/vim-compiler-go'
" Plugin 'dgryski/vim-godef'
" Plugin 'davidhalter/jedi-vim'
" Plugin 'scrooloose/syntastic'

call vundle#end()            " required
filetype plugin indent on    " required

nmap <C-h> <C-w>h
nmap <C-l> <C-w>l
nmap <C-j> <C-w>j
nmap <C-k> <C-w>k

map <C-n> :NERDTreeToggle<CR>
map <C-t> :b 1 <CR>


Bundle 'majutsushi/tagbar'
nmap <Leader>t :TagbarToggle<CR>
let g:tagbar_width = 25
autocmd VimEnter * nested :call tagbar#autoopen(1)
autocmd BufWritePre *.go:Fmt
let g:tagbar_right = 1
let g:Tlist_Ctags_Cmd='/usr/local/Cellar/ctags/5.8_1/bin/ctags'

let g:molokai_original = 1
let g:rehash256 = 1
set sw=4

colorscheme molokai

set nu
set ts=4
set expandtab
syntax on

let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_structs = 1
let g:go_highlight_operators = 1
let g:go_highlight_build_constraints = 1
let g:go_fmt_command = "goimports"
let g:go_fmt_fail_silently = 1
let g:syntastic_go_checkers = ['golint', 'govet', 'errcheck']
let g:syntastic_mode_map = { 'mode': 'active', 'passive_filetypes': ['go'] }

let g:UltiSnipsExpandTrigger="<C-g>"

let g:godef_split=2
let g:godef_same_file_in_same_window=1

au FileType go nmap <leader>r <Plug>(go-run)
au FileType go nmap <leader>b <Plug>(go-build)
au FileType go nmap <leader>T <Plug>(go-test)
au FileType go nmap <leader>c <Plug>(go-coverage)

au FileType go nmap <Leader>ds <Plug>(go-def-split)
au FileType go nmap <Leader>dv <Plug>(go-def-vertical)
au FileType go nmap <Leader>dt <Plug>(go-def-tab)

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

set rtp+=$GOPATH/src/github.com/golang/lint/misc/vim
autocmd BufWritePost,FileWritePost *.go execute 'Lint' | cwindow
set completefunc=emoji#complete
map <C-e> :%s/:\([^:]\+\):/\=emoji#for(submatch(1), submatch(0))/g <CR>

set lines=120 columns=150
```

启动vim 执行 :PluginInstall

# 安装YouCompleteMe
安装brew ctags cmake:
```
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew install cmake
brew install ctags-exuberant
```

必须要安装好golang再进行以下步骤

```
cd ~/.vim/bundle/YouCompleteMe
./install.py --clangd-completer --go-completer
```

# 初始化vim-go
启动vim执行 :GoInstallBinaries (要访问golang官网，所以你懂的)

# 安装颜色主题
```
git clone https://github.com/tomasr/molokai ~/.vim
mv ~/.vim/molokai/colors ~/.vim
```
# 常用快捷键
Ctrl n 文件目录
, t 函数列表
,dt 跳转到函数定义

# 更多内容
为什么写这篇文章，因为[fist](https://github.com/fanux/fist) 的webterminal里会集成这样一个vim，webterminal就具备非常强大的k8s管理能力，特别是编写yaml配置文件，就可以做到比如你输入一个dep补全后就直接生成一个Deployment配置，非常高效，还语法高亮，yaml语法检测等，是不是很期待~

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
