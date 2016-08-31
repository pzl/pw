pw
===

`pw` is a simple password manager for linux that encrypts your password list as a file on your machine. No cloud services (unless you set up your own). No GPG asymmetric keys required. Reasonably small list of dependencies.

It was based on Jason Dononfeld's [pass](http://www.passwordstore.org) with the following goals as changes:
- move to symmetric encryption (simpler setup, ability to easily rotate password)
- encrypt whole directory at rest (not leak meta info)
- XDG support

Installation
-------------

`make install` should move everything into place for you


Dependencies
-------------

- **bash**
  + http://www.gnu.org/software/bash/
- **GnuPG2** (as encryption engine)
  + http://www.gnupg.org/

  Optional Dependencies:
- **xclip** (if you want to copy to clipboard)
  http://sourceforge.net/projects/xclip/
- **dmenu** (if you wish to access via `pwmenu` script)
  + http://tools.suckless.org/dmenu/
  + https://bitbucket.org/melek/dmenu2

LICENSE
-------

pw is Copyright (C) 2016 Dan Panzarella <alsoelp@gmail.com>

---

parts of `pw` are based on Password Store:

Password Store is Copyright (C) 2012 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.



    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License version 2 as 
    published by the Free Software Foundation;

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
