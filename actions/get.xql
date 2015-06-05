xquery version "3.0";

import module namespace auth = "http://max.terpstra.ca/ns/exist-annotation-store#auth" at '../modules/auth.xqm';
import module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common" at '../modules/common.xqm';
import module namespace xqjson = "http://xqilla.sourceforge.net/lib/xqjson";

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
            'actions/get.xql', 19
        )
    else if (not(auth:may-read($issuer, $user, $ann))) then
        common:error-response(
            'auth:READ_PERM_REQUIRED',
            'The current user ('||$user||') has not been given "read" permissions for annotation '||$annotationId,
            'actions/get.xql', 25
        )
    else
        xqjson:serialize-json($ann)
})
