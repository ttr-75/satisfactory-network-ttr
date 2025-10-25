print("Hello World")



fs = filesystem
-- Initialize /dev
if fs.initFileSystem("/dev") == false then
    computer.panic("Cannot initialize /dev")
end
-- Let say UUID of the drive is 7A4324704A53821154104A87BE5688AC
disk_uuid = "962A01B141811834C54738A9368408C8"
-- Mount our drive to root
fs.mount("/dev/" .. disk_uuid, "/")

f = fs.open("Test2", "w")

f:write("test")

local inpol = component.proxy(component.findComponent(classes.Build_IndicatorPole_C)[1])

inpol:setColor(0.0, 0.0, 1.0, 0.0)

local sppol = component.proxy(component.findComponent(classes.Build_Speakers_C)[1])

sppol:playSound("743547__aleandroct__fx-opening-message-intercom-school", 112.0)


component.proxy(component.findComponent(classes.Build_ComputerCase_C)[1])

cp = component.proxy(component.findComponent(classes.LargeControlPanel)[1])


    module = cp:getModule(0, 0);
    module2 = cp:getModule(0, 10);




    event.ignoreAll()
    event.clear()

    event.listen(module2)

    colorSw = true

    while true do
        local e, s = event.pull()
        if s == switch and e == "ChangeState" then
            if colorSw then
                module:setColor(0.0, 0.0, 1.0, 0.0);
            else
                module:setColor(0.0, 1.0, 0.0, 0.0);
            end
        end
    end
