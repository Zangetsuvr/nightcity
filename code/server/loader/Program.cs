using System.Runtime.InteropServices;

internal class Program
{
    // Login check hook in the native server (AuthAPI.h). Not part of the
    // generated bindings, so it's imported directly.
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int AuthenticateCallback(IntPtr username, IntPtr token);

    [DllImport("Server.Native", CallingConvention = CallingConvention.Cdecl)]
    private static extern void CyberpunkMP_SetAuthenticateCallback(AuthenticateCallback callback);

    private static AuthenticateCallback? s_authenticate;

    private static int Authenticate(IntPtr usernamePtr, IntPtr tokenPtr)
    {
        try
        {
            var authenticator = CyberpunkSdk.Authentication.Authenticator;
            if (authenticator == null)
                return (int)CyberpunkSdk.AuthResult.Accepted;

            var username = Marshal.PtrToStringUTF8(usernamePtr) ?? "";
            var token = Marshal.PtrToStringUTF8(tokenPtr) ?? "";
            return (int)authenticator(username, token);
        }
        catch (Exception e)
        {
            // Never let an exception cross into native code.
            Console.WriteLine($"Login check failed: {e}");
            return (int)CyberpunkSdk.AuthResult.ServerError;
        }
    }
  
    private static void SetupCallbacks()
    {
        CyberpunkMp.TUpdateCallback updateCallback = new CyberpunkMp.TUpdateCallback(Server.Loader.Server.Update);
        GCHandle.Alloc(updateCallback);
        CyberpunkMp.ServerAPI.SetUpdateCallback(updateCallback);

        CyberpunkMp.TPlayerEvent joinCallback = new CyberpunkMp.TPlayerEvent(Server.Loader.Server.PlayerJoin);
        GCHandle.Alloc(joinCallback);
        CyberpunkMp.ServerAPI.SetPlayerJoinCallback(joinCallback);

        CyberpunkMp.TPlayerEvent leaveCallback = new CyberpunkMp.TPlayerEvent(Server.Loader.Server.PlayerLeft);
        GCHandle.Alloc(leaveCallback);
        CyberpunkMp.ServerAPI.SetPlayerLeftCallback(leaveCallback);

        // Kept in a static field so the delegate is never garbage collected
        // while native code holds a pointer to it.
        s_authenticate = Authenticate;
        CyberpunkMP_SetAuthenticateCallback(s_authenticate);
    }

    private static void Main(string[] args)
    {
        try
        {
            if (CyberpunkMp.ServerAPI.Initialize())
            {
                SetupCallbacks();

                CyberpunkMp.ServerAPI.Run();
            }
        }
        catch (Exception e)
        {
            Console.WriteLine(e);
        }
        finally
        {
            CyberpunkMp.ServerAPI.Exit();
        }
    }
}