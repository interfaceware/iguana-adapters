-- This module is an example of an adapter to connect to salesforce.

-- http://help.interfaceware.com/v6/salesforce-com-adapter

-- Please consult the above URL for information on getting
-- the credentials required to authenticate this adapter.

local store2 = require 'store2'

local DbSchema = require 'dbs.api'

require 'net.http.cache'

local Store = store2.connect(iguana.project.guid().."salesforce")

-- These are default objects you can access.  If you want more objects you can specify them in the objects
-- argument to salesforce.connect.
-- Example objects QueueSobject, Account, Community, Contact, ContentDocument, Document, Product2, Event, Group, Note, Profile, Task, TaskPriority, TaskStatus, User
-- See https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_objects_list.htm
local sales_objects = "user,account,contact,opportunity,note,opportunityLineItem,pricebookEntry"

local function GetCache(Key, CacheTimeout)
   if (CacheTimeout == 0) then
      return nil
   end
   local CacheTime = Store:get(Key.."T")
   if (os.ts.difftime(os.ts.time(), CacheTime) < CacheTimeout) then
      local CachedData = Store:get(Key)
      local R = json.parse{data=CachedData}
      return R
   end
   return nil
end

local function PutCache(Key, Value)
   Store:put(Key, Value)
   Store:put(Key.."T", os.ts.time())
end

local function GetAccessTokenViaHTTP(CacheKey,T)
   local Url = 'https://login.salesforce.com/services/oauth2/token'
   local Auth = {grant_type = 'password',
      client_id = T.consumer_key,
      client_secret = T.consumer_secret,
      username = T.username,
      password = T.password}
   local J = net.http.post{url=Url,
      parameters = Auth,
      live=true}
   PutCache(CacheKey, J)
   local AccessInfo = json.parse(J)
   return AccessInfo
end

local function CheckClearCache(DoClear)
   if DoClear then
      Store:reset()
   end
end

local function DefFileName()
   return "salesforce_objects_"..iguana.project.guid()..".json"
end

local BuiltMethods = nil

local function ResetObjectCache()
   BuiltMethods = false
   local ConfigFile = DefFileName()
   os.remove(ConfigFile)
end

local function queryObjects(S, T)
   if (T.where) then
      T.query = T.query.." WHERE "..T.where
   end
   if (T.limit) then
      T.query = T.query.." LIMIT "..T.limit
   end
   local P ={parameters={q=T.query}, url=S.instance_url..T.path,
             headers={Authorization="Bearer ".. S.access_token}, cache_time=T.cache_time, live=true}
  
   local R=net.http.get(P)
   R = json.parse{data=R}
   if #R > 0 and R[1].errorCode then
      if R[1].message:find("No such column") then
         ResetObjectCache()
      end
      error(R[1].message,4)
   end
   return R
end


local function selectQuery(T)
   local R = 'SELECT Id';
   for K in pairs(T.fields) do
      R = R..","..K
   end
   R = R.." FROM "..T.object
   return R
end

local dbs_grammar = {}

local function listObjects(S,T,D)
   T = T or {}
   T.query = selectQuery(D)
   T.path = '/services/data/v20.0/query' 
   local R = queryObjects(S,T) 
   local T = dbs_grammar:tables(D.object)
   local Data = T[D.object]
   for i=1,#R.records do 
      local Row = Data[i]
      for K, V in pairs(R.records[i]) do 
         trace(K,V)
         if type(V) == 'boolean' then   
            Row[K] = tostring(V)
         elseif K == 'attributes' then
            -- Do nothing
         else
            Row[K] = V
         end
      end
   end
   return T
end



local SalesforceDbsMap={
   boolean="string",   
   datetime="datetime",
   reference="string",
   string="string",
   email="string",
   picklist="string",
   url="string",
   phone="string",
   date="datetime",
   textarea="string",
   percent="double",
   int="integer",
   currency="double",
   double="double"
}

local function GenerateDbsGrammar(Defs)
   local Schema = DbSchema()
   for ObjName,Cols in pairs(Defs.objects) do
      local T = Schema:table{name=ObjName}
      T:addColumn{name="Id", type=dbs.string, key=true}
      for ColName, Info in pairs(Cols.fields) do
         trace(ColName, Info.dtype)
         local Type = SalesforceDbsMap[Info.dtype]
         if not Type then 
            error(ColName.. " " ..Info.dtype.." is not mapped.")
         end
         T:addColumn{name=ColName, type=SalesforceDbsMap[Info.dtype]}
      end
      Schema:addGroup{name=ObjName, table_list={ObjName}}
   end
   local Dbs = Schema:dbs()
   dbs_grammar = dbs.init{definition=Dbs}
end


local salesmethods = {}
local MetaTable = {}
MetaTable.__index = salesmethods;

local function GenerateListMethod(Name, Info)
   local FName = Name..'List'
   salesmethods[FName] = function(S,T) return listObjects(S,T,Info) end;
   local F = salesmethods[FName]
   local Help = {}
   Help.Desc = "Query list of "..Name
   Help.ParameterTable = true
   Help.Parameters = {}
   Help.Parameters[1] = {limit={Opt=true, Desc="Limit the number of results - default is no limit."}}
   Help.Parameters[2] = {where={Opt=true, Desc="Give a WHERE clause."}}
   Help.Parameters[3] = {cache_time={Opt=true, Desc="Specific time to cache results (seconds). Default is 0 seconds."}}
   help.set{input_function=F, help_data=Help}         
end

local function ParseResult(Returned)
   if #Returned == 0 then
      return {}
   end
   local R = json.parse{data=Returned}
   if #R > 0 and R[1].errorCode then
      error(R[1].message,4)
   end
   return R
end

local function deleteObject(S, T, ObjectName)
   local Live = not iguana.isTest() or T.live
   local Path = S.instance_url..
       '/services/data/v20.0/sobjects/'..ObjectName..'/'..T.id
   local Headers={}
   Headers['Content-Type']='application/json'
   Headers.Authorization ="Bearer ".. S.access_token        
   local Returned = net.http.put{data=json.serialize{data=T}, method='DELETE',headers=Headers, 
      url=Path,live=Live}
   return ParseResult(Returned)   
end

local function GenerateDeleteMethod(Name, Info)
   local FName = Name..'Delete'
   salesmethods[FName] = function (S,T) return deleteObject(S,T,Info.object) end
   local F = salesmethods[FName]
   local Help = {}
   Help.Desc = "Delete a "..Name
   Help.ParameterTable = true
   Help.Parameters = {}
   Help.Parameters[1] = {id={Desc="Unique id of "..Name.." that will be deleted."}}
   Help.Parameters[2] = {live={Opt=true, Desc="Set to true to make this command work in the editor.  Default is false."}}
   help.set{input_function=F, help_data=Help}      
end

local function GenerateNewMethod(Name, Info)
   local FName = Name..'New'
   salesmethods[FName] = function (S) return dbs_grammar:tables(Name) end
   local F = salesmethods[FName]
   local Help = {}
   Help.Desc = "Returns a new "..Name.." record to populate."
   Help.ParameterTable = false
   Help.Usage = "local Record = S:"..FName.."()"
   Help.Parameters = {}
   help.set{input_function=F, help_data=Help}         
end

local function patchObject(S, T, Info)
   local ObjectName = Info.object
   local Live = not iguana.isTest() or T.live
   local Path = S.instance_url..
       '/services/data/v20.0/sobjects/'..ObjectName..'/'
   local Method
   local TableSet = T.data
   trace(TableSet)
   local Table = TableSet[ObjectName]
   
   -- We could consider iterating through all the objects supplied here
   local Data = T.data[ObjectName][1]
   trace(Path)
   local Headers={}
   Headers['Content-Type']='application/json'
   Headers.Authorization ="Bearer ".. S.access_token
   local J= {}
   local Id 
   if (not Data.Id:isNull()) then
      trace("Updating");
      Method = 'PATCH'
      Path = Path..Data.Id
      Id = Data.Id:S()
      Data.Id = nil
      for i=1, #Data do  
         if not Data[i]:isNull() and Info.fields[Data[i]:nodeName()].updatetable then
            J[Data[i]:nodeName()] = Data[i]
         end
      end
   else  
      trace("New record");
      Method = 'POST'
      for i=1, #Data do  
         if not Data[i]:isNull() and 
            (Info.fields[Data[i]:nodeName()].updatetable or
               Info.fields[Data[i]:nodeName()].createable) then
            J[Data[i]:nodeName()] = Data[i]
         end
      end
   end
   local Json = json.serialize{data=J}
   local Returned = net.http.put{data=Json, method=Method,headers=Headers, 
      url=Path,live=T.live}
   local R = ParseResult(Returned)
   if Id then
      return Id
   else
      return R.id
   end   
end

local function GenerateModifierMethod(Name, Info)
   local FName = Name..'Modify'
   salesmethods[FName] = function (S,T) return patchObject(S, T, Info) end
   local F = salesmethods[FName]
   local Help = {}
   Help.Desc = "Create or update a "..Name
   Help.ParameterTable = true
   Help.Parameters = {}
   Help.Parameters[1] = {data={Desc="Records generated from "..Name.."New."}}
   Help.Parameters[2] = {live={Opt=true, Desc="If live is true the action will be performed in the editor"}}
   help.set{input_function=F, help_data=Help}      
end

local function ObjectName(Name)
   return Name:sub(1,1):lower()..Name:sub(2)
end

local function DescribeApi(S, Object)
   local Url = S.instance_url..'/services/data/v20.0/sobjects/'..Object..'/describe/'
   trace(Url)
   local Headers={}
   Headers['Content-Type']='application/json'
   Headers.Authorization ="Bearer ".. S.access_token 
   local R = net.http.get{headers=Headers, live=true, url=Url, parameters={}} 
   return json.parse{data=R}
end

local function GenerateAPI(S, Object)
   local Info = DescribeApi(S,Object)
   if not Info.fields then
      if "NOT_FOUND" == Info[1].errorCode then
         error("There is no sales force object called "..Object, 5)
      end
   end
   local CName = ObjectName(Object)
   local Def = {}
   Def.object = Object
   Def.fields ={}
   for i=1, #Info.fields do
      local FieldInfo = Info.fields[i]
      local Name = FieldInfo.name
      trace(Name)
      trace(Info.fields[i])
      if Name ~= 'Id' then
         local Field = {}
         Field.dtype = FieldInfo.type
         Field.updatetable = FieldInfo.updateable
         Field.createable = FieldInfo.createable
         Field.desc = '?'
         Def.fields[Name] = Field
      end
   end
   return Def
end

local function GetDefinitions(S)
   local Def = {}
   Def.objects = {}
   local Objects = Def.objects
   local ApiList = sales_objects:split(",")
   for i=1, #ApiList do
      Objects[ApiList[i]] = GenerateAPI(S, ApiList[i])
   end
   Def.updated = os.ts.time()
   Def.objlist = sales_objects
   return Def
end

local function LoadDefinitions()
   local ConfigFile = DefFileName()
   if os.fs.stat(ConfigFile) then
      local F = io.open(ConfigFile, "r")
      local C = F:read("*a")
      F:close()
      local Def = json.parse{data=C}
      if Def.objlist ~= sales_objects then
         return nil
      end
      return Def
   end
   return nil
end

local function SaveDefinitions(Def)
   local ConfigFile = DefFileName()
   local F = io.open(ConfigFile, "w")
   F:write(json.serialize{data=Def, compact=true})
   F:close()
end

local function ObjectDefinitions(S)
   local Def
   Def = LoadDefinitions()
   if not Def then
      Def = GetDefinitions(S)
      SaveDefinitions(Def)
   end
   return Def
end

local function BuildMethods(Defs)
   GenerateDbsGrammar(Defs)
   for K,V in pairs(Defs.objects) do
      GenerateListMethod(K,V)
      GenerateModifierMethod(K,V)
      GenerateDeleteMethod(K,V)
      GenerateNewMethod(K,V)
   end
end


local function SalesforceConnect(T)
   CheckClearCache(T.clear_cache)
   local P = GetCache(T.consumer_key, 1800) or
             GetAccessTokenViaHTTP(T.consumer_key, T)
   
   if T.objects then
      sales_objects = T.objects
   end
   
   setmetatable(P, MetaTable)
   if not BuiltMethods then
      local Def = ObjectDefinitions(P)  
      BuildMethods(Def)
      -- comment this to false to test the
      -- above code
      BuiltMethods = true
   end
   return P
end


local helpinfo = {}

local HelpConnect = [[{"SeeAlso":[{"Title":"Salesforce.com Adapter","Link":"http://help.interfaceware.com/v6/salesforce-com-adapter"},
                                  {"Title":"The Salesforce website","Link":"http://www.salesforce.com"}],
                "Returns":[{"Desc":"The salesforce.com website <u>string</u>."}],
                "Title":"SalesforceConnect",
         "Parameters":[{"username":{"Desc":"User ID to login with <u>string</u>."}},
                       {"password":{"Desc":"Password of that user ID  <u>string</u>."}},
                       {"consumer_key":{"Desc":"Consumer key for this connected app  <u>string</u>."}},
                       {"consumer_secret":{"Desc":"Consumer secret for this connected app  <u>string</u>."}},
                       {"clear_cache":{"Opt" : true,"Desc":"If this is set to true then then the SQLite cache used to improve performace will be cleared  <u>boolean</u>."}},
                       {"objects": {"Opt" : true, "Desc" : "Optional list of objects to expose in the adapter <u>table</u>."} }],
         "ParameterTable": true,
         "Examples":["-- Connect using hard coded parameters - not recommended
local C = SalesforceConnect{clear_cache=false,
   username='sales@interfaceware.com', 
   password='mypassword', 
   consumer_secret='585519048400883388', 
   consumer_key='3MVG9KI2HHAq33RyfdfRmZyEybpy7b_bZtwCyJW7e._mxrVtsrbM.g5n3.fIwK3vPGRl2Ly2u7joju3yYpPeO' }",
"-- Connect using stored ecrypted parameters - recommended
   local ConsumerKey    = config.load{config='salesforce_consumer_key'   , key=StoreKey}
   local Password       = config.load{config='salesforce_password'       , key=StoreKey}
   local ConsumerSecret = config.load{config='salesforce_consumer_secret', key=StoreKey}
   local UserName       = config.load{config='salesforce_username'       , key=StoreKey}
      
   local C = SalesforceConnect{username=UserName, objects=SalesObjects,
      password=Password, consumer_key=ConsumerKey,  consumer_secret=ConsumerSecret}"],
         "Usage":"SalesforceConnect{username=&lt;value&gt;, password=&lt;value&gt;, consumer_key=&lt;value&gt;,
                  consumer_secret=&lt;value&gt; [, clear_cache=&lt;value&gt;] [, objects=&lt;value&gt;]}",
         "Desc":"Returns a connection object to a specified salesforce instance"}]]

help.set{input_function=SalesforceConnect, help_data=json.parse{data=HelpConnect}}

return SalesforceConnect