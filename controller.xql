xquery version "3.0";

import module namespace xqjson="http://xqilla.sourceforge.net/lib/xqjson";

declare default element namespace "http://exist.sourceforge.net/NS/exist";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

(: figure out the base URL from the request :)
(: why isn't this something eXist's app framework does already?! :)
declare variable $protocolAndDomain := replace(request:get-url(), '^(https?://[^/]+)/.*$', '$1');
declare variable $baseUrl := (
    $protocolAndDomain ||
    request:get-context-path() ||
    $exist:prefix ||
    $exist:controller
);
declare variable $baseUrlJson as element() := (
    <pair name="baseURL" type="string">{ $baseUrl }</pair>
);


if ($exist:path = '' or $exist:path = '/') then
    <dispatch>
        <forward url="{$exist:controller}/actions/index.xql">
            <set-attribute name="baseUrl" value="{$baseUrl}"/>
        </forward>
        <cache-control cache="yes"/>
    </dispatch>
    
else if (matches($exist:path, '^/annotations(/|\.json)?$')) then
    <dispatch>
        <forward url="{
            switch (upper-case(request:get-method()))
                case 'POST' return $exist:controller||'/actions/create.xql'
                default return $exist:controller||'/actions/search.xql'
        }">
            <set-attribute name="baseUrl" value="{$baseUrl}"/>
        </forward>
    </dispatch>

else if (matches($exist:path, '^/annotations/[A-Za-z0-9-_]+$')) then
    switch (upper-case(request:get-method()))
        case 'PUT' return
            <dispatch>
                <forward url="{$exist:controller}/actions/update.xql">
                    <set-attribute name="annotationId" value="{replace($exist:resource, '\.json$', '')}"/>
                    <set-attribute name="baseUrl" value="{$baseUrl}"/>
                </forward>
            </dispatch>
        case 'POST' return (
            response:set-status-code(405), (: method not allowed :)
            response:set-header('Allow', 'HEAD, GET, PUT'),
            util:declare-option("exist:serialize", "method=text media-type=application/json"),
            <response>{
            xqjson:serialize-json(
                <json type="object">
                    <pair name="status" type="number">405</pair>
                    <pair name="developerMessage" type="string">POST is only allowed on the collection (/annotations) according to the Store plugin documentation. Use PUT to update.</pair>
                    <pair name="moreInfo" type="string">http://docs.annotatorjs.org/en/v1.2.x/storage.html</pair>
                    { $baseUrlJson }
                </json>
            )
            }</response>
        )
        case 'DELETE' return
            <dispatch>
                <forward url="{$exist:controller}/actions/delete.xql">
                    <set-attribute name="annotationId" value="{replace($exist:resource, '\.json$', '')}"/>
                    <set-attribute name="baseUrl" value="{$baseUrl}"/>
                </forward>
            </dispatch>
        default return
            <dispatch>
                <forward url="{$exist:controller}/actions/get.xql">
                    <set-attribute name="annotationId" value="{replace($exist:resource, '\.json$', '')}"/>
                    <set-attribute name="baseUrl" value="{$baseUrl}"/>
                </forward>
            </dispatch>

else if (matches($exist:path, '^/search(\.json)?$')) then
    <dispatch>
        <forward url="{$exist:controller}/actions/search.xql">
            <set-attribute name="baseUrl" value="{$baseUrl}"/>
        </forward>
        <cache-control cache="yes"/>
    </dispatch>
    
else (
    response:set-status-code(404), (: not found :)
    util:declare-option("exist:serialize", "method=text media-type=application/json"),
    <response>{
    xqjson:serialize-json(
        <json type="object">
            <pair name="status" type="number">404</pair>
            { $baseUrlJson }
        </json>
    )
    }</response>
)
