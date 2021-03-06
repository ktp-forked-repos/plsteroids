:- dynamic
        package/1.

:- use_module(library(listing)).
:- set_setting(listing:tab_distance, 0).

package(xlibrary).
package(assertions).
package(xtools).
package(rtchecks).
package(refactor).
package(playground).
package(smtp).
package(clpcd).

:- [plsdirs].
:- [pltools].

:- assertz(ref_msgtype:rstats_db).
