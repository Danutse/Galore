# ============================================================
# LAUNCHER RECYCLE HELPER MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherRecycleHelper"
    LoadOrder = 100
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("GaloreDropHelper.Exports")
}

# ============================================================
# OLE RECYCLE DROP HELPER
# ============================================================

if(-not ("GaloreDropHelper.Exports" -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms.dll `
    -TypeDefinition @"

using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Threading;
using System.Windows.Forms;


namespace GaloreDropHelper
{


    public static class Exports
    {


        private static readonly object syncRoot =
        new object();



        private static DropTarget target;



        private static Thread dropThread;



        private static SynchronizationContext dropContext;



        private static IntPtr registeredHandle =
        IntPtr.Zero;



        public static void AttachRecycleDrop(
            IntPtr buttonHandle
        )
        {


            lock(syncRoot)
            {


                if(
                    dropThread != null
                )
                {


                    return;


                }


            }



            ManualResetEvent ready =
            new ManualResetEvent(
                false
            );



            bool readySignaled =
            false;



            Thread thread =
            new Thread(
                delegate()
                {


                    int oleResult =
                    OleInitialize(
                        IntPtr.Zero
                    );



                    ApplicationContext applicationContext =
                    null;



                    try
                    {


                        WindowsFormsSynchronizationContext context =
                        new WindowsFormsSynchronizationContext();



                        SynchronizationContext.SetSynchronizationContext(
                            context
                        );



                        applicationContext =
                        new ApplicationContext();



                        DropTarget newTarget =
                        new DropTarget();



                        int registerResult =
                        RegisterDragDrop(
                            buttonHandle,
                            newTarget
                        );



                        if(
                            registerResult != 0
                        )
                        {


                            return;


                        }



                        lock(syncRoot)
                        {


                            target =
                            newTarget;



                            dropContext =
                            context;



                            registeredHandle =
                            buttonHandle;


                        }



                        readySignaled =
                        true;



                        ready.Set();



                        Application.Run(
                            applicationContext
                        );


                    }
                    catch
                    {



                    }
                    finally
                    {


                        if(
                            registeredHandle != IntPtr.Zero
                        )
                        {


                            RevokeDragDrop(
                                registeredHandle
                            );


                        }



                        lock(syncRoot)
                        {


                            registeredHandle =
                            IntPtr.Zero;



                            target =
                            null;



                            dropContext =
                            null;



                            dropThread =
                            null;


                        }



                        if(
                            applicationContext != null
                        )
                        {


                            applicationContext.Dispose();


                        }



                        if(
                            oleResult >= 0
                        )
                        {


                            OleUninitialize();


                        }



                        if(
                            !readySignaled
                        )
                        {


                            ready.Set();


                        }


                    }


                }
            );



            thread.IsBackground =
            true;



            thread.SetApartmentState(
                ApartmentState.STA
            );



            lock(syncRoot)
            {


                dropThread =
                thread;


            }



            thread.Start();



            if(
                ready.WaitOne(
                    3000
                )
            )
            {


                ready.Close();


            }


        }



        public static void DetachRecycleDrop()
        {


            Thread thread;



            SynchronizationContext context;



            lock(syncRoot)
            {


                thread =
                dropThread;



                context =
                dropContext;


            }



            if(
                thread == null
            )
            {


                return;


            }



            if(
                context != null
            )
            {


                context.Post(
                    delegate(object state)
                    {


                        Application.ExitThread();


                    },
                    null
                );


            }



            if(
                Thread.CurrentThread != thread
            )
            {


                thread.Join(
                    3000
                );


            }


        }







        [DllImport(
            "ole32.dll"
        )]
        private static extern int OleInitialize(
            IntPtr pvReserved
        );



        [DllImport(
            "ole32.dll"
        )]
        private static extern void OleUninitialize();








        [DllImport(
            "ole32.dll"
        )]
        private static extern int RegisterDragDrop(
            IntPtr hwnd,
            IDropTarget target
        );



        [DllImport(
            "ole32.dll"
        )]
        private static extern int RevokeDragDrop(
            IntPtr hwnd
        );


    }









    [ComVisible(true)]
    [ClassInterface(
        ClassInterfaceType.None
    )]
    public class DropTarget :
    IDropTarget
    {




        public int DragEnter(
            System.Runtime.InteropServices.ComTypes.IDataObject dataObject,
            uint keyState,
            POINTL point,
            ref uint effect
        )
        {


            effect =
            1;


            return 0;


        }







        public int DragOver(
            uint keyState,
            POINTL point,
            ref uint effect
        )
        {


            effect =
            1;


            return 0;


        }







        public int DragLeave()
        {


            return 0;


        }







        public int Drop(
            System.Runtime.InteropServices.ComTypes.IDataObject dataObject,
            uint keyState,
            POINTL point,
            ref uint effect
        )
        {


            effect =
            1;



            try
            {


                FORMATETC format =
                new FORMATETC();



                format.cfFormat =
                15;



                format.dwAspect =
                DVASPECT.DVASPECT_CONTENT;



                format.lindex =
                -1;



                format.tymed =
                TYMED.TYMED_HGLOBAL;




                STGMEDIUM medium;



                dataObject.GetData(
                    ref format,
                    out medium
                );




                IntPtr hDrop =
                medium.unionmember;




                uint count =
                DragQueryFile(
                    hDrop,
                    0xffffffff,
                    null,
                    0
                );




                for(
                    uint i = 0;
                    i < count;
                    i++
                )
                {


                    uint length =
                    DragQueryFile(
                        hDrop,
                        i,
                        null,
                        0
                    );



                    char[] buffer =
                    new char[length + 1];



                    DragQueryFile(
                        hDrop,
                        i,
                        buffer,
                        (uint)buffer.Length
                    );



                    string file =
                    new string(
                        buffer
                    ).TrimEnd(
                        '\0'
                    );


                }





                ReleaseStgMedium(
                    ref medium
                );


            }
            catch
            {

            }




            return 0;


        }









        [DllImport(
            "shell32.dll",
            CharSet = CharSet.Unicode
        )]
        private static extern uint DragQueryFile(
            IntPtr hDrop,
            uint index,
            [Out] char[] file,
            uint length
        );










        [DllImport(
            "ole32.dll"
        )]
        private static extern void ReleaseStgMedium(
            ref STGMEDIUM medium
        );



    }









    [ComImport]
    [Guid(
        "00000122-0000-0000-C000-000000000046"
    )]
    [InterfaceType(
        ComInterfaceType.InterfaceIsIUnknown
    )]
    public interface IDropTarget
    {


        int DragEnter(
            System.Runtime.InteropServices.ComTypes.IDataObject dataObject,
            uint keyState,
            POINTL point,
            ref uint effect
        );



        int DragOver(
            uint keyState,
            POINTL point,
            ref uint effect
        );



        int DragLeave();



        int Drop(
            System.Runtime.InteropServices.ComTypes.IDataObject dataObject,
            uint keyState,
            POINTL point,
            ref uint effect
        );


    }








    [StructLayout(
        LayoutKind.Sequential
    )]
    public struct POINTL
    {

        public int x;

        public int y;

    }



}

"@
}
