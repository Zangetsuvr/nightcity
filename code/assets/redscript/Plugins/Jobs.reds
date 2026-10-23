module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*

public class JobEntry {
    let id: Uint32;
    let name: String;
    let description: String;
    let reward: Uint32;
}

public struct JobInfo {
    let id: Uint32;
    let name: String;
    let description: String;
    let reward: Uint32;
}

public native class JobsServer extends ServerRpc {
    public static native func SelectJob(job: CName) -> Void;
    public static native func QuitJob() -> Void;
}

public class JobsClient extends ClientRpc {

    // Kept for the server's call when a job starts or ends; the job board
    // (Plugins/JobBoard.reds) now shows everything, so nothing opens here.
    public func SetActiveJob(job: CName) -> Void {
    }
}
