# Priority

Ranges may nest (a note on 75 inside 70–80) and partially overlap (70–80 and 75–85) now that we have ranges attached to annotations.

## What gets edited/selected

Two lookups:

- **starts on**: the bookmark whose first line is the cursor line
- **innermost**: starts on, else the smallest range containing the line

### Cases

Range 70–80, single on 75.

| Action          | Cursor | Result                     |
| --------------- | ------ | -------------------------- |
| annotate        | 70     | edits the range            |
| annotate        | 75     | edits the single           |
| annotate        | 76     | creates a single on 76     |
| visual annotate | 70–85  | resizes the range to 70–85 |
| visual annotate | 72–78  | creates a range 72–78      |
| delete / toggle | 75     | the single                 |
| delete / toggle | 76     | the range                  |
| next / prev     |        | stops at 70, then 75       |

So, basically think of the rule like this:
Annotate looks at the start line under the cursor (in x modes, the top selected line). If an annotation starts there, we edit it. If there is none present, then we will create.

On delete or toggle, the annotation with the starting line on the cursor will be used, or else the innermost (smallest) ranged annotation containing the line.

Having many annotations on one start line is a rare case, and it happens when we delete a bookmarked line. See the next section.

### Stacked start lines

Creation never puts two bookmarks on one start line. Edits can: bookmarks on 3 and 4, `dd` line 3, and both sit on 3. Undo splits them again, so they are never merged.

Tie-break: single before range, then the smaller range, then the older one.
