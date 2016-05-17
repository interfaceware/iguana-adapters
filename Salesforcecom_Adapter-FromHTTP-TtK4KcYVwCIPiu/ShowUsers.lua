

local function ShowUsers(C)
   local U = C:userList{}
 
   local R = 'List of salesforce users:\n'
   for i=1, #U.user do
      trace(U.user[i].FirstName.." "..U.user[i].LastName)
      R = R..U.user[i].FirstName.." "..U.user[i].LastName.."\n"
   end
   
   net.http.respond{body=R, entity_type='text/plain'}
end

return ShowUsers