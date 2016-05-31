-- This is an example of using the Iguana salesforce adapter.

-- http://help.interfaceware.com/v6/salesforce-com-adapter

-- Please consult the above URL for information on getting
-- the credentials required to authenticate this adapter.

local SalesforceConnect = require 'salesforce'

local config = require 'encrypt.password'

local StoreKey = "dfsdfasdfadsfsa"

-- These are some examples with the salesforce connector
local MakeJiffyAccount = require 'MakeJiffyAccount'
local ShowUsers        = require 'ShowUsers'

-- It's good practice to avoid saving your passwords in the repository.
-- So we use the encrypt.password module:
-- http://help.interfaceware.com/v6/encrypt-password-in-file

-- You'll need to:
--  A) Edit these values saved here.
--  B) Then uncomment the lines.
--  C) Then comment the lines out again
--  D) Then obfuscate your password from this Lua file *BEFORE* your next milestone commit.
--config.save{config='salesforce_consumer_key', password='', key=StoreKey}
--config.save{config='salesforce_consumer_secret', password='', key=StoreKey}
--config.save{config='salesforce_username', password='', key=StoreKey}
--config.save{config='salesforce_password', password='', key=StoreKey}

-- See https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_objects_list.htm
-- for a list of potential salesforce.com objects to put here. Each company tends to choose very specific
-- parts of salesforce.com to implement so it makes sense to select just the objects that your implementation
-- uses.
local SalesObjects= "user,account,contact,opportunity,note,opportunityLineItem,pricebookEntry,queueSobject"

function main(Data)
   local ConsumerKey    = config.load{config="salesforce_consumer_key"   , key=StoreKey}
   local Password       = config.load{config="salesforce_password"       , key=StoreKey}
   local ConsumerSecret = config.load{config="salesforce_consumer_secret", key=StoreKey}
   local UserName       = config.load{config="salesforce_username"       , key=StoreKey}
      
   local C = SalesforceConnect{username=UserName, objects=SalesObjects,
      password=Password, consumer_key=ConsumerKey,  consumer_secret=ConsumerSecret}
     
   MakeJiffyAccount(C)
   ShowUsers(C)
end
