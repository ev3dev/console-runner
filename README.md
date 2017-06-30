console-runner
==============

D-Bus client/server for running programs on a remote virtual console.


Documentation
-------------

* [Online](doc/)
* `man console-runner`


Hacking
-------

    sudo apt update
    sudo apt install cmake pandoc valac
    git clone --recursive https://github.com/ev3dev/console-runner
    cd console-runner
    cmake -P setup.cmake
    make -C build
