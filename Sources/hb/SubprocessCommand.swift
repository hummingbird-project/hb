import Subprocess

struct SubprocessCommand {
    let executable: Executable
    let arguments: Arguments

    init(_ executable: Executable, arguments: Arguments) {
        self.executable = executable
        self.arguments = arguments
    }

    init(_ executable: Executable, arguments: [String]) {
        self.executable = executable
        self.arguments = .init(arguments)
    }
}
