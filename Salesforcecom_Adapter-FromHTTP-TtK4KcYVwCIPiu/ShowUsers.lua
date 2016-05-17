local function ShowUsers(C)
   -- This example we just display the users of the instance
   -- of salesforce.com
   local U = C:userList{}
 
   local R = 'List of salesforce users:\n'
   -- Loop through all the users and append them to a list.
   for i=1, #U.user do
      trace(U.user[i].FirstName.." "..U.user[i].LastName)
      R = R..U.user[i].FirstName.." "..U.user[i].LastName.."\n"
   end

   -- Display the list
   net.http.respond{body=R, entity_type='text/plain'}
end

return ShowUsers