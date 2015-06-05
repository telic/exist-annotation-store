xquery version "3.0";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/json";

import module namespace xqjson="http://xqilla.sourceforge.net/lib/xqjson";

xqjson:serialize-json(
    <json type="object">
        <pair name="name" type="string">Annotator Store API</pair>
        <pair name="version" type="string">2.0.0</pair>
        <pair name="baseURL" type="string">{request:get-attribute('baseUrl')}</pair>
        <pair name="urls" type="object">
            <pair name="create" type="string">/annotations</pair>
            <pair name="update" type="string">/annotations/:id</pair>
            <pair name="destroy" type="string">/annotations/:id</pair>
            <pair name="search" type="string">/search</pair>
        </pair>
    </json>
)