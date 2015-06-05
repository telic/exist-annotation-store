xquery version "3.0";
module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common";

import module namespace xqjson = "http://xqilla.sourceforge.net/lib/xqjson";
import module namespace xmldb = "http://exist-db.org/xquery/xmldb";

(: common error codes :)
declare variable $common:ID_IN_USE := xs:QName('common:ID_IN_USE');
declare variable $common:NO_SUCH_ANNOTATION := xs:QName('common:NO_SUCH_ANNOTATION');
declare variable $common:JSON_PARSE_ERR := xs:QName('common:JSON_PARSE_ERR');
declare variable $common:ANN_NON_OBJECT := xs:QName('common:ANN_NON_OBJECT');
declare variable $common:INVALID_DATETIME := xs:QName('common:INVALID_DATETIME');
declare variable $common:USER_FORGERY := xs:QName('common:USER_FORGERY');
declare variable $common:INVALID_USER := xs:QName('common:INVALID_USER');
declare variable $common:MISSING_RANGES := xs:QName('common:MISSING_RANGES');
declare variable $common:INVALID_RANGES := xs:QName('common:INVALID_RANGES');
declare variable $common:INVALID_RANGE := xs:QName('common:INVALID_RANGE');
declare variable $common:MISSING_RANGE_ITEM := xs:QName('common:MISSING_RANGE_ITEM');
declare variable $common:PERM_NON_OBJECT := xs:QName('common:PERM_NON_OBJECT');
declare variable $common:INVALID_PERM := xs:QName('common:INVALID_PERM');
declare variable $common:MISSING_QUOTE := xs:QName('common:MISSING_QUOTE');
declare variable $common:MISSING_TEXT := xs:QName('common:MISSING_TEXT');
declare variable $common:INVALID_QUOTE := xs:QName('common:INVALID_QUOTE');
declare variable $common:INVALID_TEXT := xs:QName('common:INVALID_TEXT');
declare variable $common:UNSUPPORTED_CONTENT := xs:QName('common:UNSUPPORTED_CONTENT');
declare variable $common:INVALID_ID := xs:QName('common:INVALID_ID');

(:~
 : @param $err an error code from the common or auth modules
 : @return a simple error message corresponding to the given error code
 :)
declare function common:message-for-error($err as xs:string) as xs:string? {
    switch ($err)
    case 'common:ID_IN_USE'
    case 'common:ANN_NON_OBJECT'
    case 'common:INVALID_DATETIME'
    case 'common:INVALID_RANGES'
    case 'common:INVALID_RANGE'
    case 'common:MISSING_RANGE_ITEM'
    case 'common:USER_FORGERY'
    case 'common:INVALID_USER'
    case 'common:MISSING_TEXT'
    case 'common:MISSING_QUOTE'
    case 'common:MISSING_RANGES'
    case 'common:INVALID_QUOTE'
    case 'common:INVALID_RANGES'
    case 'common:MISSING_USER'
    case 'common:PERM_NON_OBJECT'
    case 'common:INVALID_PERM'
    case 'common:JSON_PARSE_ERR'
    case 'common:UNSUPPORTED_CONTENT'
    case 'common:INVALID_ID'
        return 'This annotation appears to be invalid'
    case 'common:NO_SUCH_ANNOTATION'
        return 'This annotation does not exist'
    case 'auth:UPDATE_PERM_REQUIRED'
    case 'auth:ADMIN_PERM_REQUIRED'
    case 'auth:READ_PERM_REQUIRED'
    case 'auth:DELETE_PERM_REQUIRED'
    case 'auth:UNKNOWN_ISSUER'
    case 'auth:UNKNOWN_KEY'
        return 'You are not authorized to perform this action'
    case 'auth:MISSING_JWT'
        return 'You must be signed in to access this resource'
    case 'auth:MISSING_USER'
    case 'auth:MISSING_ISS'
    case 'auth:INVALID_JWT'
    case 'auth:INVALID_USER'
        return 'There was an error verifying your account credentials'

    default return ()
};

(:~
 : @param $err an error code from the common or auth modules
 : @return the most appropriate HTTP status code for the given error
 :)
declare function common:status-for-error($err as xs:string) as xs:integer {
    switch ($err)
    case 'common:NO_SUCH_ANNOTATION'
        return 404 (: Not Found :)
    case 'auth:MISSING_JWT'
        return 401 (: Unauthorized :)
    case 'auth:UPDATE_PERM_REQUIRED'
    case 'auth:ADMIN_PERM_REQUIRED'
    case 'auth:READ_PERM_REQUIRED'
    case 'auth:DELETE_PERM_REQUIRED'
    case 'auth:UNKNOWN_ISSUER'
    case 'auth:UNKNOWN_KEY'
        return 403 (: Forbidden :)
    case 'auth:MISSING_ISS'
    case 'auth:INVALID_JWT'
    case 'auth:INVALID_USER'
    case 'common:ID_IN_USE'
    case 'common:ANN_NON_OBJECT'
    case 'common:INVALID_DATETIME'
    case 'common:INVALID_RANGES'
    case 'common:INVALID_RANGE'
    case 'common:MISSING_RANGE_ITEM'
    case 'common:INVALID_USER'
    case 'common:USER_FORGERY'
    case 'common:MISSING_TEXT'
    case 'common:MISSING_QUOTE'
    case 'common:INVALID_TEXT'
    case 'common:INVALID_QUOTE'
    case 'common:MISSING_RANGES'
    case 'common:MISSING_USER'
    case 'common:PERM_NON_OBJECT'
    case 'common:INVALID_PERM'
    case 'common:JSON_PARSE_ERR'
    case 'common:UNSUPPORTED_CONTENT'
    case 'common:INVALID_ID'
        return 400 (: Bad Request :)

    default return 400 (: Bad Request :)
};

(:~ the site ID, used to identify this installation :)
declare variable $common:site-id as xs:string := string(
    doc('../store-configuration.xml')/store-configuration/site-id
);

(:~ the absolute path to the root of this application :)
declare variable $common:application-root as xs:string := util:collection-name(doc('../repo.xml'));

(:~ the absolute path to a collection for storing temporary files :)
declare variable $common:temp-collection as xs:string :=
    let $tmpDir := $common:application-root||'/temp'
    return
        if (xmldb:collection-available($tmpDir)) then $tmpDir
        else xmldb:create-collection($common:application-root, 'temp')
;

(:~
 : A hack to work around bug in fn:collection with relative paths
 :
 : @param $rel collection path, relative to the root of this application
 : @return the collection
 :)
declare function common:collection($rel as xs:string?) as node()* {
    collection(
        $common:application-root||'/'||$rel
    )
};

(:~
 : Generate a JSON error response document, using the default status and
 : message for the given error code.
 : Note: this method changes the response status and serialization options.
 :
 : @param $code application-specific error code
 : @param $devMessage a detailed error message, appropriate for a technical audience
 : @param $file file the error occured in, relative to the root of the GitHub repository
 : @param $line line number the error occurred on
 : 
 : @return the JSON response
 :)
declare function common:error-response(
    $code as xs:string,
    $devMessage as xs:string?,
    $file as xs:string?,
    $line as xs:positiveInteger?
) as xs:string {
    let $message := common:message-for-error($code),
        $status := common:status-for-error($code)
    return
        common:error-response($status, $message, $code, $devMessage, $file, $line)
};

(:~
 : Generate a JSON error response document.
 : Note: this method changes the response status and serialization options.
 : 
 : @param $status HTTP status code
 : @param $message user-friendly error message
 : @param $code application-specific error code
 : @param $devMessage more detailed error message, appropriate for a technical audience
 : @param $file file the error occured in, relative to the root of the GitHub repository
 : @param $line line number the error occurred on
 : 
 : @return the JSON response
 :)
declare function common:error-response(
    $status as xs:positiveInteger,
    $message as xs:string?,
    $code as xs:string?,
    $devMessage as xs:string?,
    $file as xs:string?,
    $line as xs:positiveInteger?
) as xs:string {
    response:set-status-code($status),
    util:declare-option("exist:serialize", "method=text media-type=application/json"),
    xqjson:serialize-json(
        <json type="object">
            <pair name="status" type="number">{$status}</pair>
            <pair name="baseURL" type="string">{request:get-attribute('baseUrl')}</pair>
        { if ($code) then
            <pair name="errorCode" type="string">{$code}</pair>
          else () }
        { if ($message) then
            <pair name="message" type="string">{$message}</pair>
          else () }
        { if ($devMessage) then
            <pair name="developerMessage" type="string">{$devMessage}</pair>
          else() }
        { if ($file) then
            <pair name="source" type="string">{
                'https://github.com/telic/exist-annotation-store/blob/'||
                doc('../store-configuration.xml')//version ||
                '/' || $file ||
                (if ($line) then '#L' || $line else '')
            }</pair>
          else () }
        </json>
    )
};


(:~
 : Run a few more checks on client-supplied JSON that need to be passed
 : if this is being used to create a new annotation
 :
 : @param $ann the parsed JSON string as an xqjson structure
 : @param $user the client's user ID
 :
 : @error common:MISSING_RANGES
 : @error common:MISSING_QUOTE
 : @error common:MISSING_TEXT
 :
 : @return $ann if all checks pass
 :)
declare function common:extra-checks($ann as element(json), $user as xs:string) as element(json) {
    if (empty($ann/pair[@name='ranges'][@type='array'])) then
        error($common:MISSING_RANGES, 'a "ranges" array property is required')
    else if (empty($ann/pair[@name='text'])) then
        error($common:MISSING_TEXT, 'a "text" string property is required')
    else if (empty($ann/pair[@name='quote'])) then
        error($common:MISSING_QUOTE, 'a "quote" string property is required')
    else $ann
};

(:~
 : Parse client-supplied annotation JSON, and do some basic checks
 :
 : @param $ann the raw JSON string
 : @param $user the client's user ID
 :
 : @error common:JSON_PARSE_ERR
 : @error common:ANN_NON_OBJECT
 : @error common:INVALID_DATETIME
 : @error common:USER_FORGERY
 : @error common:INVALID_RANGE
 : @error common:MISSING_RANGE_ITEM
 : @error common:PERM_NON_OBJECT
 : @error common:INVALID_PERM
 : @error common:INVALID_ID
 :
 : @return an xqjson:parse-json() result
 :)
declare function common:parse-and-check($ann as xs:string, $user as xs:string) as element(json) {
    let $xqj := try {
            xqjson:parse-json($ann)
        }
        catch * {
            error($common:JSON_PARSE_ERR, $err:description, $err:value)
        },
        $dup := ($xqj//pair[@name = ((./parent::*/pair except .)/@name)])[1]/@name,
        $badRange := $xqj/pair[@name='ranges']/item[@type != 'object' or count((
                pair[@name='end'][@type='string'],
                pair[@name='start'][@type='string'],
                pair[@name='endOffset'][@type='number'],
                pair[@name='startOffset'][@type='number']
            )) lt 4][1]
    return
        (: if there are duplicate keys :)
        if ($dup) then
            error($common:JSON_PARSE_ERR, 'duplicate object key "'||$dup||'"')

        (: if this isn't an object :)
        else if ($xqj[@type != 'object']) then
            error($common:ANN_NON_OBJECT, 'Annotation must be a JSON object')

        (: if the ID is given but isn't a proper ID string :)
        else if (
            $xqj/pair[@name='id'][@type != 'string'] or
            (
                exists($xqj/pair[@name='id']) and
                not(matches($xqj/pair[@name='id'], '^[A-Za-z0-9-_]+$'))
            )
        ) then
            error($common:INVALID_ID, 'Invalid "id" specified; IDs must be simple strings matching the regex "^[A-Za-z0-9-_]+$".')

        (: if created isn't a datetime string :)
        else if (common:invalid-dateTime($xqj, 'created')) then
            error($common:INVALID_DATETIME, 'The supplied "created" property is not a valid dateTime')

        (: if updated isn't a datetime string :)
        else if (common:invalid-dateTime($xqj, 'updated')) then
            error($common:INVALID_DATETIME, 'The supplied "updated" property is not a valid dateTime')

        (: if the user property isn't a string :)
        else if ($xqj/pair[@name='user'][@type != 'string']) then
            error($common:INVALID_USER, 'User IDs must be strings')

        (: if the client tries to provide an incorrect user field :)
        else if ($xqj/pair[@name='user'] != $user) then
            error($common:USER_FORGERY, 'The supplied "user" property does not match the current user')

        (: if ranges is malformed :)
        else if ($xqj/pair[@name='ranges'][@type != 'array']) then
            error(
                $common:INVALID_RANGES,
                'property "ranges" must be an array'
            )
        else if ($badRange) then
            error(
                $common:INVALID_RANGE,
                'invalid range specified; ranges should look like {"start":"..", "startOffset":123, "end":"..", "endOffset":123}',
                xqjson:serialize-json($badRange)
            )
        else if (
            exists($xqj/pair[@name='ranges']) and
            empty($xqj/pair[@name='ranges']/item[@type='object'][
                pair[@name='end'][@type='string'] and
                pair[@name='start'][@type='string'] and
                pair[@name='endOffset'][@type='number'] and
                pair[@name='startOffset'][@type='number']
            ])
        ) then
            error($common:MISSING_RANGE_ITEM, 'at least one "range" item is required')

        (: if permissions is not an object :)
        else if ($xqj/pair[@name='permissions'][@type != 'object']) then
            error($common:PERM_NON_OBJECT, 'the "permissions" property must be an object')
        (: if any of the permission properties are objects or
           if any of the permission properties' items are not strings :)
        else if (
            $xqj/pair[@name='permissions']/pair[@type='object'] or
            $xqj/pair[@name='permissions']/pair/item[@type != 'string']
        ) then
            error($common:INVALID_PERM, '"permissions" properties should be arrays of string values')

        (: if quote or text is mis-typed :)
        else if ($xqj/pair[@name='quote'][@type!='string']) then
            error($common:INVALID_QUOTE, 'property "quote" must be a string')
        else if ($xqj/pair[@name='text'][@type!='string']) then
            error($common:INVALID_TEXT, 'property "text" must be a string')

        (: if we got this far, all's well! :)
        else $xqj
};

declare %private function common:invalid-dateTime($ann, $field) as xs:boolean {
    if (
        $ann/pair[@name=$field][@type != 'string']
        or
        (
            exists($ann/pair[@name=$field]) and
            not($ann/pair[@name=$field] castable as xs:dateTime)
        )
    )
    then true()
    else false()
};

declare function common:get-request-data() as xs:string {
    let $type := request:get-header('Content-Type')
    let $data := request:get-data()
    return
        if (
            empty($type) or
            matches($type, '^(application|text)/json(;|$)') or
            matches($type, '^text/javascript(;|$)')
        ) then
            if ($data instance of xs:base64Binary) then
                util:binary-to-string($data)
            else (: $data instance of xs:string :)
                string($data)
        else
            error($common:UNSUPPORTED_CONTENT, 'the "'||request:get-header('Content-Type')||'" content type is not supported. Please provide annotation data as JSON ("application/json").')
};
