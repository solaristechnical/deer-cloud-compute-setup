# test_long_paths.rb
# Test for long path support in Ruby environment
# Usage: modelkit ruby test_long_paths.rb

require("fileutils")
require("fiddle")
require("tmpdir")

def green(text)
    return "\e[32m#{text}\033[0m"
end

def red(text)
    return "\e[31m#{text}\033[0m"
end

def are_long_paths_enabled()
    # Check if long paths are enabled in the Windows environment
    # First, import the native NTDLL library
    begin
        require("fiddle")
        ntdll = Fiddle.dlopen("ntdll.dll")
        # RtlAreLongPathsEnabled is an internal Windows API function
        rtlAreLongPathsEnabled = Fiddle::Function.new(
            ntdll["RtlAreLongPathsEnabled"],
            [],
            Fiddle::TYPE_INT
        )
        return rtlAreLongPathsEnabled.call() != 0
        # If the call succeeds, the result has already been returned
    rescue
        return false
    end
end

# Check if Ruby was built with Long Path support
def ruby_built_with_long_path_support()
    return false unless RUBY_PLATFORM =~ /mswin|mingw/

    begin
        Dir.mktmpdir("ruby-long-path-support-") do |directory|
            directory = File.expand_path(directory).tr("/", "\\")
            prefix = directory.start_with?("\\\\") ? "\\\\?\\UNC\\#{directory[2..-1]}" : "\\\\?\\#{directory}"
            longFolder = File.join(prefix, "a" * 130, "b" * 130)
            longPath = File.join(longFolder, "test.txt")
            begin
                FileUtils.mkdir_p(longFolder)
                File.write(longPath, "Test content")
                return File.read(longPath) == "Test content"
            ensure
                FileUtils.rm_rf(File.join(prefix, "a" * 130))
            end
        end
    rescue SystemCallError, IOError
        return false
    end
end

def testLongPaths(drive="C:\\")
    # Write a file with a long path to confirm that LongPathsEnabled is actually working.
    # If it works, return true. If it fails, return false.
    begin
        longFolder = File.join(drive, "Temp", "a" * 130, "b" * 130)
        longPath = File.join(longFolder, "test.txt")
        FileUtils.mkdir_p(longFolder)
        File.write(longPath, "Test content")
        File.delete(longPath)
        FileUtils.rm_rf(longFolder)
        return true
    rescue
        return false
    end
end

def main()
    # Echo Ruby version
    puts "Ruby version: #{RUBY_VERSION}"
    # Create an empty hash to store test results as a local variable
    test_results = Hash.new
    test_results["Long paths enabled and Ruby is aware"] = are_long_paths_enabled()
    test_results["Ruby built with Long Path support"] = ruby_built_with_long_path_support()
    test_results["Long paths test C:\\"] = testLongPaths()
    prefix = "\\\\?\\c:\\"
    test_results["Long paths test #{prefix}"] = testLongPaths(drive=prefix)
    prefix = "\\\\?\\UNC\\LOCALHOST\\c$"
    test_results["Long paths test #{prefix}"] = testLongPaths(drive=prefix)

    test_results.each do |test, result|
        # Use terminal colors red and green for failed and passed tests respectively
        puts "#{test}: #{result ? green('Passed') : red('Failed')}"
    end
end

main()
