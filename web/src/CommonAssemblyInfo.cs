using System.Reflection;
using System.Runtime.InteropServices;

// Common assembly info shared by all projects/assemblies

#if DEBUG
    [assembly: AssemblyConfiguration("Debug")]
#else
    [assembly: AssemblyConfiguration("Release")]
#endif

[assembly: AssemblyCompany("SDL Group")]
[assembly: AssemblyProduct("SDL Digital Experience Accelerator")]

[assembly: ComVisible(false)]

// NOTE: Version Info and Copyright statement is automatically appended by the build process (ciBuild.proj)
[assembly: AssemblyVersion("1.6.0.0")]
[assembly: AssemblyFileVersion("1.6.0.223")]
[assembly: AssemblyInformationalVersion("1.6.0")]
[assembly: AssemblyCopyright("Copyright © 2014-2016 SDL Group")]
