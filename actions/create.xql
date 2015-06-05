xquery version "3.0";

import module namespace auth = "http://max.terpstra.ca/ns/exist-annotation-store#auth" at '../modules/auth.xqm';
import module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common" at '../modules/common.xqm';
import module namespace xqjson = "http://xqilla.sourceforge.net/lib/xqjson";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/json";

(: provided by the controller :)
declare variable $baseUrl := request:get-attribute('baseUrl');

auth:get-account-then(function($issuer, $user) {
    try {
        let $json := common:get-request-data(),
            $parsed := common:extra-checks(
                    common:parse-and-check($json, $user), $user
                ),
            $id := string(($parsed/pair[@name='id'][@type='string'], util:uuid())[1]),
            $_ := if (exists(doc('../annotations/'||$issuer||'/'||$id||'.xml')))
                then error($common:ID_IN_USE, 'ID '||$id||' is already in use by another annotation')
                else (),
            (: store in a temporary folder so we can do updates :)
            $tmp := doc(xmldb:store($common:temp-collection, util:uuid()||'.xml', $parsed))
        return (

            (: make sure the 'user' field is set :)
            if (empty($parsed/pair[@name='user'])) then
                update insert <pair name='user' type='string'>{$user}</pair> into $tmp/json
            else (),

            (: make sure the 'id' field is set :)
            if (empty($parsed/pair[@name='id'])) then (
                update insert <pair name='id' type='string'>{$id}</pair> into $tmp/json
            ) else (),

            (: fix any wierd/missing permissions :)
            auth:fix-permissions($tmp/json, $issuer, $user),

            (: fill in the 'created' and 'updated' times :)
            if (empty($parsed/pair[@name='created'])) then
                update insert <pair name="created" type="string">{current-dateTime()}</pair>
                    into $tmp/json
            else(),
            if (empty($parsed/pair[@name='updated'])) then
                update insert <pair name="updated" type="string">{current-dateTime()}</pair>
                    into $tmp/json
            else (),

            (: move the fixed file into place :)
            xmldb:store(
                $common:application-root||'/annotations/'||$issuer,
                $id||'.xml',
                $tmp
            ),
            xmldb:remove(
                $common:temp-collection,
                util:document-name($tmp)
            ),

            (: and respond with the updated version and a canonical redirect :)
            (: THIS DOESN'T WORK IN CHROMIUM/WEBKIT :)
            (: response:set-status-code(303), : See Other  :)
            (: response:set-header('Location', $baseUrl||'/annotations/'||$id), :)
            response:set-status-code(200),
            xqjson:serialize-json(doc('../annotations/'||$issuer||'/'||$id||'.xml')/json)

        )[last()]
    }
    (: note: this should be common:*, but eXist barfs on that :)
    catch * {
        common:error-response(
            $err:code, $err:description,
            'modules/common.xqm', $err:line-number
        )
    }
})