local function MakeJiffyAccount(C)
   local AccountName = "Jiffy Dry Cleaning"
   -- For this query we are disabling caching of the results - hence
   -- cache_time = 0
   local JiffyAccount = C:accountList{where="Name = '"..AccountName.."'",
       cache_time=0}
   if #JiffyAccount.account == 0 then
      -- We could not find the Jiffy Account so lets create a new record
      -- This method gives us an empty record to populate
      JiffyAccount = C:accountNew()
   end
   
   A = JiffyAccount.account[1]
   A.Name = AccountName
   A.Industry = "Dry Cleaner"
   -- accountModify is how we actually submit the new or modified account
   local JiffyId = C:accountModify{data=JiffyAccount, live=true}
   C:accountDelete{id=JiffyId}
end

return MakeJiffyAccount