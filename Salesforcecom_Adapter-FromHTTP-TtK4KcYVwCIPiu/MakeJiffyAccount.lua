
local function MakeJiffyAccount(C)
      local AccountName = "Jiffy Dry Cleaning"
   local JiffyAccount = C:accountList{where="Name = '"..AccountName.."'",
       cache_time=0}
   if #JiffyAccount.account == 0 then
      -- We could not find the 
      JiffyAccount = C:accountNew()
   end
   
   A = JiffyAccount.account[1]
   A.Name = AccountName
   A.Industry = "Dry Cleaner"
   local JiffyId = C:accountModify{data=JiffyAccount, live=true}
   C:accountDelete{id=JiffyId}
end

return MakeJiffyAccount