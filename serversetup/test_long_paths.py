# test_long_paths.py
import ctypes
import os

def green(text):
    return f"\033[92m{text}\033[0m"

def red(text):
    return f"\033[91m{text}\033[0m"

def are_long_paths_enabled():
    ntdll = ctypes.WinDLL('ntdll')
    # RtlAreLongPathsEnabled is an internal Windows API function
    if hasattr(ntdll, 'RtlAreLongPathsEnabled'):
        ntdll.RtlAreLongPathsEnabled.restype = ctypes.c_ubyte
        ntdll.RtlAreLongPathsEnabled.argtypes = ()
        return bool(ntdll.RtlAreLongPathsEnabled())
    return False

def testLongPaths(drive="C:\\"):
    # Write a file with a long path to confirm that LongPathsEnabled is actually working.
    longFolder = os.path.join(drive, "Temp", ("a" * 130), ("b" * 130))
    longPath = os.path.join(longFolder, "test.txt")
    try:
        os.makedirs(longFolder, exist_ok=True)
        with open(longPath, "w") as f:
            f.write("Test content")
        
        print("Successfully created a file with a long path.")
        os.remove(longPath)
        os.rmdir(longFolder)
        return True
    except FileNotFoundError:
        print("❌ Failed. The system rejected the path length.")
        return False
    except PermissionError:
        print("⚠️ Permission issue, but path limit wasn't necessarily the failure trigger.")
        return False
    except:
        print("Failed to create a file with a long path.")
        import traceback
        traceback.print_exc()
        return False

# Inspect Ruby.exe application manifest for long paths support
def inspect_ruby_manifest_for_long_paths(
        ruby_exe_path = "C:\\Program Files (x86)\\Modelkit Caboodle\\ruby\\ruby-2.0.0\\bin\\ruby.exe"
):
    import pefile
    pe = pefile.PE(ruby_exe_path)
    
    # The application manifest must have this element in the XML: <ws2:longPathAware>true</ws2:longPathAware>
    # TODO Implement the actual inspection logic using pefile as needed
    header = pe.dump_info()
    print(header)
    return False

if __name__ == "__main__":
    
    TestResults = {}
    
    TestResults["Long paths enabled in Windows"] = are_long_paths_enabled()
    
    TestResults["Long paths test C:\\"] = testLongPaths()
    
    prefix = "\\\\?\\c:\\"
    TestResults[f"Long paths test {prefix}"] = testLongPaths(drive=prefix)
    
    prefix = "\\\\?\\UNC\\LOCALHOST\\c$"
    TestResults[f"Long paths test {prefix}"] = testLongPaths(drive=prefix)
    
    TestResults["Inspect Ruby manifest for long paths (modelkit)"] = inspect_ruby_manifest_for_long_paths()
    
    # If you have manually installed some other Ruby versions, you can add similar tests here.
    #TestResults["Inspect Ruby manifest for long paths (C:\\Ruby200-x64)"] = \
    # inspect_ruby_manifest_for_long_paths("C:\\Ruby200-x64\\bin\\ruby.exe")
    #TestResults["Inspect Ruby manifest for long paths (C:\\Ruby33-x64)"] = \
    # inspect_ruby_manifest_for_long_paths("C:\\Ruby33-x64\\bin\\ruby.exe")
    
    for test, result in TestResults.items():
        # Use terminal colors red and green for failed and passed tests respectively
        print(f"{test}: {green('Passed') if result else red('Failed')}")
