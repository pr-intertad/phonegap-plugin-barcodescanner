package com.google.zxing.vin;

import com.google.zxing.FormatException;

public class VIN {

    public static boolean validateVIN(String vin) throws FormatException {
        int[] values = {1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 0, 7, 0, 9,
                2, 3, 4, 5, 6, 7, 8, 9};
        int[] weights = {8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2};

        String s = vin;
        s = s.replaceAll("-", "");
        s = s.replaceAll(" ", "");
        s = s.toUpperCase();

        if (s.length() != 17) {
            // VIN number must be 17 characters
            throw FormatException.getFormatInstance();
        }

        int sum = 0;
        for (int i = 0; i < 17; i++) {
            char c = s.charAt(i);
            int value;
            int weight = weights[i];

            // letter
            if (c >= 'A' && c <= 'Z') {
                value = values[c - 'A'];
                if (value == 0) {
                    // Illegal character
                    throw FormatException.getFormatInstance();
                }
            }

            // number
            else if (c >= '0' && c <= '9') {
                value = c - '0';
            }
            // illegal character
            else {
                throw FormatException.getFormatInstance();
            }

            sum = sum + weight * value;
        }

        // check digit
        sum = sum % 11;
        char check = s.charAt(8);
        if (sum == 10 && check == 'X') {
            return true;
        } else if (sum == transliterate(check)) {
            return true;
        } else {
            throw FormatException.getFormatInstance();
        }

    }

    private static int transliterate(char check) {
        if (check == 'A' || check == 'J') {
            return 1;
        } else if (check == 'B' || check == 'K' || check == 'S') {
            return 2;
        } else if (check == 'C' || check == 'L' || check == 'T') {
            return 3;
        } else if (check == 'D' || check == 'M' || check == 'U') {
            return 4;
        } else if (check == 'E' || check == 'N' || check == 'V') {
            return 5;
        } else if (check == 'F' || check == 'W') {
            return 6;
        } else if (check == 'G' || check == 'P' || check == 'X') {
            return 7;
        } else if (check == 'H' || check == 'Y') {
            return 8;
        } else if (check == 'R' || check == 'Z') {
            return 9;
        } else if (Integer.valueOf(Character.getNumericValue(check)) != null) { //hacky but works
            return Character.getNumericValue(check);
        }
        return -1;
    }

}