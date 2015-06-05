xquery version "3.0";

import module namespace sm="http://exist-db.org/xquery/securitymanager";

(: the target collection into which the app is deployed :)
declare variable $target external;

(: generate a unique store ID for use as JWT 'audience' :)
let $id := doc($target||'/store-configuration.xml')/store-configuration/site-id
return
    if ($id = '') then
        update value $id with util:uuid()
    else ()
,
(: create 'annotations' and 'issuers' collections :)
(: and limit access to them :)
(: note: removing 'x' privilege causes problems with REST for some reason... :)
for $dir in ('annotations', 'issuers')
return (
    xmldb:create-collection($target, $dir),
    sm:chmod(xs:anyURI($target||'/'||$dir), 'rwxr-x--x')
)
,
(: add setuid to all action xqueries :)
for $q in collection($target||'/actions')
return
    sm:chmod(
        xs:anyURI(util:collection-name($q)||'/'||util:document-name($q)),
        'rwsr-xr-x'
    )
,
(: also setuid auth.xqm :)
sm:chmod(
    xs:anyURI($target||'/modules/auth.xqm'),
    'rwsr-xr-x'
)
