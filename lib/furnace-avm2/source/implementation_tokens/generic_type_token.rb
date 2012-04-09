module Furnace::AVM2::Tokens
  class GenericTypeToken < Furnace::Code::SeparatedToken
    include IsEmbedded
    include IsSimple

    def text_between
      "."
    end
  end
end