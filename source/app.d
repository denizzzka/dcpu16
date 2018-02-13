import dlangui;

mixin APP_ENTRY_POINT;

extern (C) int UIAppMain(string[] args)
{
    Window window = Platform.instance.createWindow("DCPU-16 emulator", null);

    window.mainWidget = parseML(q{
        VerticalLayout
        {
            TextWidget { text: "Hello World example for DlangUI"; textColor: "red"; fontSize: 150%; fontWeight: 800; fontFace: "Arial" }
            // arrange controls as form - table with two columns

            HorizontalLayout {
                Button { id: btnOk; text: "Ok" }
                Button { id: btnCancel; text: "Cancel" }
            }
        }
    });


    // show window
    window.show();

    // run message loop
    return Platform.instance.enterMessageLoop();
}
