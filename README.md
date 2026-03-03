# -AList控制器-
安卓版AList的控制器使用termux运行，脚本跟AList二进制文件放在一起，脚本会识别当前文件夹里面的AList二进制文件  
脚本里面的下载更新AList可能没用。可以试一下，但是可能没用，建议还是在官网下载后放在一起。

运行脚本代码 sh AList-Controller (注:这条指令需要在脚本文件的文件所在位置运行，用Termux下载的不要用这条指令)

建议使用Termux

Termux下载链接 https://github.com/termux/termux-app/releases


Mt管理器也可以用，因为不按流程退出会有进程残留，所以不推荐(注:此方法必须要root)

Termux下载脚本链接指令:curl -L -O https://raw.githubusercontent.com/kdivfv/AList-Controller/refs/heads/main/AList控制器.sh  
下载完后执行指令:sh AList控制器.sh (注:在Termux下载的才执行这一个，同样要跟下载好的AList二进制文件放在一起，这条指令也需要在脚本文件的文件所在位置运行)

无法下载先运行这条指令安装环境 pkg install curl
