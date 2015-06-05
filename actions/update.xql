xquery version "3.0";

import module namespace auth = "http://max.terpstra.ca/ns/exist-annotation-store#auth" at '../modules/auth.xqm';
import module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common" at '../modules/common.xqm';
import module namespace xqjson = "http://xqilla.sourceforge.net/lib/xqjson";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/json";

(: provided by the controller :)
declare variable $annotationId := request:get-attribute('annotationId');
declare variable $baseUrl := request:get-attribute('baseUrl');

auth:get-account-then(function($issuer, $user) {
    try {
        let $json := common:get-request-data(),
            $parsed := common:parse-and-check($json, $user),
            $old := doc('../annotations/'||$issuer||'/'||$annotationId||'.xml')/json,
            $newId := string(($parsed/pair[@name='id'], $annotationId)[1])

        return

        (: can't update an annotation that doesn't exist yet :)
        if (empty($old)) then
            error($common:NO_SUCH_ANNOTATION, 'Annotation "'||$annotationId||'" does not exist. Use POST on /annotations to create something new')

        (: must have permission to update :)
        else if (not(auth:may-update($issuer, $user, $parsed))) then
            error($auth:UPDATE_PERM_REQUIRED, 'The current user ('||$user||') has not been given the "update" permission for this annotation, and so cannot make changes')

        (: can't rename to an ID that's already in use :)
        else if (
            $newId != $annotationId and
            exists(doc('../annotations/'||$issuer||'/'||$newId||'.xml'))
        ) then
            error($common:ID_IN_USE, 'The requested ID "'||$newId||'" is already in use by another annotation')

        (: only some users are allowed to change permissions :)
        else if (
            auth:permissions-differ(
                $parsed/pair[@name='permissions'],
                $old/pair[@name='permissions']
            ) and
            not(auth:may-admin($issuer, $user, $old))
        ) then
            error($auth:ADMIN_PERM_REQUIRED, 'The current user ('||$user||') has not been given the "admin" permission for this annotation, and so cannot change its permissions')

        (: only some users are allowed to change the annotation's owner :)
        else if (
            $old/pair[@name='user'] != $parsed/pair[@name='user'] and
            not(auth:may-admin($issuer, $user, $old))
        ) then
            error($auth:ADMIN_PERM_REQUIRED, 'The current user ('||$user||') has not been given the "admin" permission for this annotation, and so cannot change its owning user')

        else
        let $tmp := doc(xmldb:store($common:temp-collection, util:uuid()||'.xml', $parsed))
        return (

            (: copy in data from the old version :)
            for $prop in $old/pair return
            if (empty($parsed/pair[@name=$prop/@name])) then
                update insert $prop into $tmp/json
            else (),

            (: update the "updated" field :)
            if (empty($parsed/pair[@name='updated'])) then
                update value $tmp/json/pair[@name='updated'] with current-dateTime()
            else (),

            (: fix permissions :)
            auth:fix-permissions($tmp/json, $issuer, $user),

            (: move the fixed file into place :)
            xmldb:store(
                $common:application-root||'/annotations/'||$issuer,
                $newId||'.xml',
                $tmp
            ),
            xmldb:remove(
                $common:temp-collection,
                util:document-name($tmp)
            ),
            (: and remove the old one, if the ID changed :)
            if ($newId != $annotationId) then
                xmldb:remove(
                    $common:application-root||'/annotations/'||$issuer,
                    $annotationId||'.xml'
                )
            else (),

            (: lastly, respond with the updated version and a canonical redirect :)
            if ($newId != $annotationId) then (
                (: response:set-status-code(303) : See Other  :)
                (: response:set-header('Location', $baseUrl||'/annotations/'||$newId), :)
                response:set-status-code(200)
            ) else
                response:set-status-code(200)
            ,
            xqjson:serialize-json(doc('../annotations/'||$issuer||'/'||$newId||'.xml')/json)

        )[last()]
    }
    (: note: this should be common:* | auth:*, but eXist barfs on that :)
    catch * {
        common:error-response(
            $err:code, $err:description,
            'actions/update.xql', $err:line-number
        )
    }

})
