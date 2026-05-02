using System.Collections.Generic;
using System.Text;

public static class CSVParser
{
    public static List<string[]> Parse(string csvText)
    {
        var result = new List<string[]>();
        if (string.IsNullOrEmpty(csvText))
        {
            return result;
        }

        var currentRow = new List<string>();
        var currentField = new StringBuilder();
        bool inQuotes = false;

        for (int i = 0; i < csvText.Length; i++)
        {
            char c = csvText[i];

            if (inQuotes)
            {
                if (c == '"')
                {
                    if (i + 1 < csvText.Length && csvText[i + 1] == '"')
                    {
                        currentField.Append('"');
                        i++;
                    }
                    else
                    {
                        inQuotes = false;
                    }
                }
                else
                {
                    currentField.Append(c);
                }
            }
            else
            {
                if (c == '"')
                {
                    inQuotes = true;
                }
                else if (c == ',')
                {
                    currentRow.Add(currentField.ToString());
                    currentField.Clear();
                }
                else if (c == '\n' || c == '\r')
                {
                    if (c == '\r' && i + 1 < csvText.Length && csvText[i + 1] == '\n')
                    {
                        i++;
                    }
                    
                    currentRow.Add(currentField.ToString());
                    result.Add(currentRow.ToArray());
                    currentRow.Clear();
                    currentField.Clear();
                }
                else
                {
                    currentField.Append(c);
                }
            }
        }

        if (currentRow.Count > 0 || currentField.Length > 0)
        {
            currentRow.Add(currentField.ToString());
            result.Add(currentRow.ToArray());
        }

        return result;
    }
}
