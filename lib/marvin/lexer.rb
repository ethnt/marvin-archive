require 'strscan'

require_relative 'lexer/token'

module Marvin

  # The Lexer will search through the source code for Tokens.
  class Lexer
    attr_accessor :tokens, :configuration

    # Creates a new Lexer with a given source code and configuration.
    #
    # @param [String] source Source code.
    # @param [Marvin::Configuration] configuration Configuration instance.
    # @return [Marvin::Lexer] An un-run lexer.
    def initialize(source, configuration = Marvin::Configuration.new)
      @scanner = StringScanner.new(source)
      @tokens = []
      @configuration = configuration
    end

    # Run the actual lexer.
    #
    # @return [[Marvin::Token]] An Array of Tokens fromt he
    def lex!
      @configuration.logger.info 'Tokenizing...'

      # Continue until we reach the end of the string.
      until @scanner.eos?

        # If we match a space at the pointer, go to the next iteration.
        next unless @scanner.scan(/\s/).nil?

        # Set the token to nil initially.
        token = nil

        # Run through every regex at this pointer.
        Marvin::Grammar::SPECIFICATIONS.values.each do |expr|

          # If we get a match from StringScanner#match?, it will return the
          # length of the match and nil otherwise.
          len = @scanner.match?(expr)

          # We've got a match!
          if len && len > 0

            # Peek the length of the match ahead to get the lexeme.
            lexeme = @scanner.peek(len)

            # The kind matches up in the spec hash.
            kind   = Marvin::Grammar::SPECIFICATIONS.key(expr)

            # Grab the line from the overall character number.
            attrs  = {
              line: line_from_char(@scanner.pos),
              char: char_on_line(@scanner.pos),
            }

            # Make the new token.
            token = Marvin::Token.new(lexeme, kind, attrs)

            # Break out of the loop, since we've found a match.
            break
          end
        end

        # If we have a token, advance by the length of the lexeme and add the
        # token to our token array.
        if token
          @scanner.pos = @scanner.pos + token.lexeme.length
          @tokens << token

        # Otherwise, just advance by one.
        else
          @scanner.pos = @scanner.pos + 1
        end

        next
      end

      @configuration.logger.info "Found #{@tokens.count} tokens."

      # Check, please!
      @tokens
    end

    # Get the line from the overall character number.
    #
    # @param [Integer] char The overall character number in the document.
    # @return [Integer] The line number.
    def line_from_char(char)
      str = @scanner.string[0..char]
      str.lines.count
    end

    # Get the character number on its line.
    #
    # @param [Integer] char The overall character number in the document.
    # @return [Integer] The character number on its given line.
    def char_on_line(char)
      str = @scanner.string[0..char]

      if newline_char = str.rindex("\n")
        char - newline_char
      else
        char
      end
    end
  end
end
