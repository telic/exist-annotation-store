xquery version "3.0";

import module namespace auth = "http://max.terpstra.ca/ns/exist-annotation-store#auth" at '../modules/auth.xqm';
import module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common" at '../modules/common.xqm';
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/json";

(: provided by the controller :)
declare variable $annotationId := request:get-attribute('annotationId');
declare variable $baseUrl := request:get-attribute('baseUrl');

auth:get-account-then(function($issuer, $user) {
    (: find the resource :)
    let $ann := doc('../annotations/'||$issuer||'/'||$annotationId||'.xml')/json
    return
    if (empty($ann)) then
        common:error-response(
            'common:NO_SUCH_ANNOTATION',
            'Annotation "'||$annotationId||'" does not exist',
            'actions/delete.xql', 20
        )
    else if (not(auth:may-delete($issuer, $user, $ann))) then
        common:error-response(
            'common:DELETE_PERM_REQUIRED',
            'The current user ('||$user||') has not been given the "delete" permissions for this annotation',
            (: simulate an XQuery error to make this easier to find :)
            'actions/delete.xql', 26
        )
    else (
        xmldb:remove($common:application-root||'/annotations/'||$issuer, $annotationId||'.xml'),
        response:set-status-code(204) (: No Content :)
    )
})
