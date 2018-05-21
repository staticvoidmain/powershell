. .\test_helpers.ps1

# some examples of using the assertion libarary.
# written WITH the assertion library.
describe "the assertion library" {

    describe "assert_expr" {
        it "invokes an arbitrary script block" {
            assert_expr "test expression" {
                10 -lt 20 -and 0 -ne 1
            }
        }
    }

    describe "assert_throws" {
        it "passes when the script block throws" {
            assert_throws "should throw" {
                throw "oh noes!"
            }
        }
    }

    describe "assert_lessThan" {
        it "passes when actual is less than expected" {
            assert_lessThan 2 10
        }
    }

    describe "assert_lessThanEqual" {
        it "passes when actual is less than expected" {
            assert_lessThanEqual 2 10
        }

        it "passes when actual equal to expected" {
            assert_lessThanEqual 2 2
        }
    }

    describe "assert_greaterThan" {
        it "passes when actual > expected" {
            assert_greaterThan 10 2
        }
    }

    describe "assert_greaterThanEqual" {
        it "passes when actual >= expected" {
            assert_greaterThanEqual 10 2
        }
    }

    describe "assert_equal" {
        it "passes when expected == actual" {
            assert_equal 1 1
        }
    }

    describe "assert_notEqual" {
        it "passes when expected != actual" {
            assert_notEqual 0 1
        }
    }

    describe "assert_isNull" {
        it "passes when acutal is null" {
            assert_isNull $null
        }
    }

    describe "assert_isNotNull" {
        it "passes when actual is not null" {
            assert_isNotNull "non-null thing"
        }
    }

    describe "assert_isTruthy" {
        it "matches truthy values" {
            assert_isTruthy "something"
            assert_isTruthy $true
            assert_isTruthy @(1)
        }
    }

    describe "assert_isFalsy" {
        it "matches falsy values" {
            assert_isFalsy ""
            assert_isFalsy $false
            assert_isFalsy @()
        }
    }

    describe "assert_isMatch" {
        it "matches regex patterns" {
            assert_isMatch "something" "^s\w+$"
        }
    }

    describe "assert_unique" {
        it "passes" {
            assert_unique @(3, 4, 5)
        }
    }

    describe "assert_none" {
        it "ensures no elements match the value" {
            assert_none @(1, 2, 3) 10
        }
    }

    describe "assert_one" {
        it "ensures ONLY ONE matching element exists" {
            assert_one @($true, $false, $false) $true
        }
    }

    describe "assert_all" {
        it "ensures all elements are the same value" {
            assert_all @(2, 2, 2) 2
        }
    }

    describe "assert_any" {
        it "asserts at least one value matches" {
            assert_any @(1, 2, 3, 1) 1
        }
    }

    describe "assert_ordered" {
        it "supports ascending" {
            assert_ordered @(1, 2, 3, 4, 4, 5) 'asc'
        }

        it "supports descending" {
            assert_ordered @(4, 4, 2, 1) 'desc'
        }
    }
}